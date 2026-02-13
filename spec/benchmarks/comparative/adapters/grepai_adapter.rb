# frozen_string_literal: true

require "open3"
require "json"
require "yaml"

module ComparativeHelpers
  module Adapters
    # CLI-based adapter for grepai (optional competitor).
    # Local vector DB using Ollama embeddings, code-focused retrieval.
    # Skipped gracefully when grepai or Ollama is not available.
    #
    # grepai workflow:
    #   1. Create .grepai/config.yaml (GOB backend + Ollama embeddings)
    #   2. Start `grepai watch` in background (indexes on startup, then watches)
    #   3. Search via `grepai search --json -n <limit> <query>`
    #   4. Kill watch process on teardown
    class GrepaiAdapter < BaseAdapter
      INDEXING_TIMEOUT = 60

      attr_reader :last_metrics

      def initialize
        @last_metrics = {}
        @dir = nil
        @id_map = {} # filename -> dataset_id
        @watch_stdin = nil
        @watch_stdout = nil
        @watch_stderr = nil
        @watch_thread = nil
        @watch_pid = nil
      end

      def available?
        return @available unless @available.nil?

        @available = system("which grepai > /dev/null 2>&1") &&
          ollama_running?
      end

      def name
        "grepai"
      end

      def setup(facts, dir)
        @dir = dir

        # Create source files (one per fact) for grepai to index
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)

        facts.each do |fact|
          next if fact["status"] == "superseded"

          dataset_id = fact["id"]
          filename = "#{dataset_id}.rb"
          @id_map[filename] = dataset_id

          # Use code_context if available, else wrap text as a comment
          content = fact["code_context"] ||
            "# #{fact["subject"]}: #{fact["predicate"]}\n# #{fact["object"]}\n# #{fact["text"]}"

          File.write(File.join(src_dir, filename), content)
        end

        # Create config for GOB backend with Ollama (grepai init is interactive)
        config_dir = File.join(dir, ".grepai")
        FileUtils.mkdir_p(config_dir)

        config = {
          "store" => {"backend" => "gob"},
          "embedder" => {
            "provider" => "ollama",
            "model" => "nomic-embed-text",
            "endpoint" => "http://localhost:11434"
          }
        }
        File.write(File.join(config_dir, "config.yaml"), YAML.dump(config))

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Start grepai watch in background — it does initial scan then watches
        @watch_stdin, @watch_stdout, @watch_stderr, @watch_thread =
          Open3.popen3("grepai", "watch", chdir: dir)
        @watch_pid = @watch_thread.pid

        # Wait for index file to appear (indicates initial scan complete)
        index_path = File.join(config_dir, "index.gob")
        indexed = sleep_with_timeout(timeout: INDEXING_TIMEOUT) {
          File.exist?(index_path) && File.size(index_path) > 0
        }

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

        @last_metrics = {
          setup_time_ms: (elapsed * 1000).round(2),
          disk_bytes: dir_size(dir)
        }

        unless indexed
          warn "grepai indexing timed out after #{INDEXING_TIMEOUT}s in #{dir}"
        end
      end

      def search(query, limit: 10)
        return [] unless available? && @dir

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        output, status = Open3.capture2(
          "grepai", "search", "--json", "-n", limit.to_s, query,
          chdir: @dir
        )

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        @last_metrics = @last_metrics.merge(latency_ms: (elapsed * 1000).round(2))

        return [] unless status.success?

        # Parse JSON output: [{ file_path, start_line, end_line, score, content }]
        results = JSON.parse(output)
        results = [results] if results.is_a?(Hash) # Normalize single result

        results.filter_map { |r|
          path = r["file_path"] || r["FilePath"] || r["path"] || ""
          filename = File.basename(path)
          @id_map[filename]
        }.uniq.first(limit)
      rescue JSON::ParserError
        # Fall back to line-based parsing if --json isn't supported
        parse_text_output(output, limit)
      end

      def teardown
        # Kill the watch process
        begin
          Process.kill("TERM", @watch_pid) if @watch_pid
        rescue Errno::ESRCH
          # Process already exited
        end

        # Close IO objects
        [@watch_stdin, @watch_stdout, @watch_stderr].each do |io|
          io&.close
        rescue IOError
          # Already closed
        end

        @watch_thread&.value # Reap thread
        @watch_stdin = nil
        @watch_stdout = nil
        @watch_stderr = nil
        @watch_thread = nil
        @watch_pid = nil
        @dir = nil
        @id_map = {}
      end

      private

      def ollama_running?
        require "net/http"
        uri = URI("http://localhost:11434/api/tags")
        response = Net::HTTP.get_response(uri)
        response.is_a?(Net::HTTPSuccess)
      rescue
        false
      end

      def sleep_with_timeout(timeout:, interval: 0.5)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return true if yield
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          sleep(interval)
        end
      end

      def parse_text_output(output, limit)
        return [] unless output

        output.lines.filter_map { |line|
          path = line.strip.split(/\s+/).first
          next unless path
          filename = File.basename(path)
          @id_map[filename]
        }.uniq.first(limit)
      end

      def dir_size(dir)
        Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
          .select { |f| File.file?(f) }
          .sum { |f| File.size(f) }
      end
    end
  end
end
