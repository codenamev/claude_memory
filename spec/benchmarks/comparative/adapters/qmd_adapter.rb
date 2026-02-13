# frozen_string_literal: true

require "open3"
require "json"

module ComparativeHelpers
  module Adapters
    # CLI-based adapter for QMD (optional competitor).
    # Supports three search modes:
    #   :bm25   — `qmd search`  (BM25 keyword only, no models, instant)
    #   :vector — `qmd vsearch` (vector similarity, embedding model only, fast)
    #   :hybrid — `qmd query`   (expansion + BM25 + vector + reranking, slow)
    #
    # Skipped gracefully when qmd is not installed.
    class QmdAdapter < BaseAdapter
      # Ensure ~/.bun/bin is in PATH (qmd is installed via Bun)
      BUN_BIN = File.expand_path("~/.bun/bin")
      ENV["PATH"] = "#{BUN_BIN}:#{ENV["PATH"]}" unless ENV["PATH"]&.include?(BUN_BIN)

      MODES = {
        bm25: {name: "QMD-BM25", command: "search", collection: "bench_bm25", needs_embed: false},
        vector: {name: "QMD-Vector", command: "vsearch", collection: "bench_vec", needs_embed: true},
        hybrid: {name: "QMD-Hybrid", command: "query", collection: "bench_hyb", needs_embed: true}
      }.freeze

      attr_reader :last_metrics

      def initialize(mode: :bm25)
        @mode = mode
        @config = MODES.fetch(mode)
        @last_metrics = {}
        @dir = nil
        @id_map = {} # filename -> dataset_id
      end

      def available?
        @available ||= system("which qmd > /dev/null 2>&1")
      end

      def name
        @config[:name]
      end

      def setup(facts, dir)
        @dir = dir

        # Create markdown files (one per fact) for QMD to index
        docs_dir = File.join(dir, "docs")
        FileUtils.mkdir_p(docs_dir)

        facts.each do |fact|
          next if fact["status"] == "superseded"

          dataset_id = fact["id"]
          filename = "#{dataset_id}.md"
          @id_map[filename] = dataset_id

          prose = fact["prose"] || fact["text"]
          content = "# #{fact["subject"]}: #{fact["predicate"]}\n\n#{prose}"

          File.write(File.join(docs_dir, filename), content)
        end

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        collection = @config[:collection]

        # Defensively remove stale collection from previous runs
        Open3.capture2("qmd", "collection", "remove", collection)

        # Register collection
        _out, status1 = Open3.capture2(
          "qmd", "collection", "add", docs_dir, "--name", collection
        )
        unless status1.success?
          warn "QMD collection add failed in #{dir}"
          return
        end

        # Generate embeddings only if this mode needs them
        if @config[:needs_embed]
          _out, status2 = Open3.capture2("qmd", "embed")
          unless status2.success?
            warn "QMD embed failed in #{dir}"
          end
        end

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

        @last_metrics = {
          setup_time_ms: (elapsed * 1000).round(2),
          disk_bytes: dir_size(dir)
        }
      end

      def search(query, limit: 10)
        return [] unless available? && @dir

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        ids = if @mode == :bm25
          bm25_search(query, limit)
        else
          qmd_search(query, limit)
        end

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        @last_metrics = @last_metrics.merge(latency_ms: (elapsed * 1000).round(2))
        ids
      end

      def teardown
        Open3.capture2("qmd", "collection", "remove", @config[:collection]) if available?
        @dir = nil
        @id_map = {}
      end

      private

      # QMD's BM25 uses AND semantics and strips common English stopwords.
      # NL questions like "What caching solution does Acme API use?" fail because:
      # 1. QMD strips stopwords internally (what, does, the)
      # 2. Remaining words are AND-matched, so "solution" (absent from docs) kills results
      #
      # Strategy: strip our own stopwords, then retry with progressively fewer
      # words (dropping the shortest/most generic) until we get results.
      STOPWORDS = %w[
        a an and are as at be but by do does did for from had has have he her
        him his how i if in into is it its just let me my no nor not of on or
        our she so some than that the their them then there these they this to
        too us use used uses using was we what when where which who whom why
        will with would you your can could should shall may might must been being
        work works working
      ].to_set.freeze

      def bm25_search(query, limit)
        words = strip_stopwords(query).split
        return [] if words.empty?

        # QMD BM25 uses AND semantics — a single missing word kills results.
        # Try full query first, then drop one word at a time (BM25 is instant
        # so extra calls are cheap). Prefer dropping shorter/generic words first.
        ids = qmd_search(words.join(" "), limit)
        return ids if ids.any?

        # Try removing one word at a time, shortest first (most likely generic)
        words.sort_by(&:length).each do |drop|
          remaining = words.reject { |w| w == drop }
          next if remaining.empty?
          ids = qmd_search(remaining.join(" "), limit)
          return ids if ids.any?
        end

        []
      end

      def qmd_search(query, limit)
        output, status = Open3.capture2(
          "qmd", @config[:command], "--json", "-n", limit.to_s,
          "-c", @config[:collection], query
        )

        return [] unless status.success?

        results = JSON.parse(output)
        results.filter_map { |r|
          file_field = r["file"] || r["path"] || ""
          basename = File.basename(file_field)
          @id_map[basename] || @id_map[basename.tr("-", "_")]
        }.first(limit)
      rescue JSON::ParserError
        []
      end

      def strip_stopwords(query)
        query.gsub(/[?!.,;:]/, "")
          .split
          .reject { |w| STOPWORDS.include?(w.downcase) }
          .join(" ")
      end

      def dir_size(dir)
        Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
          .select { |f| File.file?(f) }
          .sum { |f| File.size(f) }
      end
    end
  end
end
