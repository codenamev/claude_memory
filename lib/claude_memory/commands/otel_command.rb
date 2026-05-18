# frozen_string_literal: true

require "optparse"
require "net/http"
require "uri"
require "json"

module ClaudeMemory
  module Commands
    # CLI shell for the OTel ingestion feature. Subcommands flip flags in
    # `.claude/settings.json` (delegated to OTel::SettingsWriter) or report
    # status (delegated to OTel::Status). The command itself contains no
    # domain logic.
    #
    #   claude-memory otel                       # default --status
    #   claude-memory otel --status
    #   claude-memory otel --enable
    #   claude-memory otel --disable
    #   claude-memory otel --enable-traces
    #   claude-memory otel --disable-traces
    #   claude-memory otel --capture-prompts    # opt-in: OTEL_LOG_USER_PROMPTS=1
    #   claude-memory otel --no-capture-prompts
    #   claude-memory otel --verify             # POST a fixture and confirm round-trip
    class OtelCommand < BaseCommand
      def call(args)
        opts = parse_options(args, default_options) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory otel [options]"
            parser.on("--status", "Show ingestion status (default)") { o[:action] = :status }
            parser.on("--enable", "Configure Claude Code to export telemetry") { o[:action] = :enable }
            parser.on("--disable", "Remove telemetry env from settings.json") { o[:action] = :disable }
            parser.on("--enable-traces", "Opt in to trace ingestion") { o[:action] = :enable_traces }
            parser.on("--disable-traces", "Tell Claude Code to skip trace export") { o[:action] = :disable_traces }
            parser.on("--capture-prompts", "Opt in to OTEL_LOG_USER_PROMPTS=1") { o[:action] = :capture_prompts }
            parser.on("--no-capture-prompts", "Stop capturing prompt content") { o[:action] = :disable_capture_prompts }
            parser.on("--verify", "Send a sample envelope and confirm it persisted") { o[:action] = :verify }
            parser.on("--port PORT", Integer, "Receiver port for the dashboard (default 3377)") { |v| o[:port] = v }
          end
        end
        return 1 if opts.nil?

        case opts[:action]
        when :enable then run_enable(opts)
        when :disable then run_disable(opts)
        when :enable_traces then run_settings_change(opts) { |w| w.enable_traces! }
        when :disable_traces then run_settings_change(opts) { |w| w.disable_traces! }
        when :capture_prompts then run_capture_prompts(opts)
        when :disable_capture_prompts then run_settings_change(opts) { |w| w.disable_capture_prompts! }
        when :verify then run_verify(opts)
        else run_status(opts)
        end
      end

      private

      def default_options
        {action: :status, port: OTel::SettingsWriter::DEFAULT_PORT}
      end

      def writer(opts)
        OTel::SettingsWriter.new(claude_dir, port: opts[:port])
      end

      def claude_dir
        File.join(ClaudeMemory::Configuration.new.project_dir, ".claude")
      end

      def run_status(opts)
        manager = Store::StoreManager.new
        manager.ensure_global! if manager.global_exists?
        store = manager.global_store
        status = OTel::Status.new(store, settings_writer: writer(opts)).snapshot

        stdout.puts "OTel telemetry status:"
        stdout.puts "  metrics ingested:    #{status[:metric_count]}"
        stdout.puts "  events ingested:     #{status[:event_count]}"
        stdout.puts "  traces ingested:     #{status[:trace_count]}  (enabled: #{status[:traces_enabled]})"
        stdout.puts "  last metric:         #{status[:last_metric_at] || "never"}"
        stdout.puts "  configured endpoint: #{status[:endpoint] || "(not configured — run --enable)"}"
        manager.close
        0
      end

      def run_enable(opts)
        result = writer(opts).enable!
        return failure("could not enable telemetry: #{result.error}") if result.failure?
        stdout.puts "Enabled OTel telemetry. Restart any active claude sessions for changes to take effect."
        stdout.puts "  endpoint: http://127.0.0.1:#{opts[:port]}"
        stdout.puts "  protocol: http/json"
        stdout.puts ""
        stdout.puts "Traces are off by default. Opt in with `claude-memory otel --enable-traces`."
        0
      end

      def run_disable(opts)
        result = writer(opts).disable!
        return failure("could not disable telemetry: #{result.error}") if result.failure?
        stdout.puts "Disabled OTel telemetry. Removed env keys from settings.json."
        0
      end

      def run_settings_change(opts)
        result = yield(writer(opts))
        return failure("settings update failed: #{result.error}") if result.failure?
        stdout.puts "Settings updated:"
        result.value.each { |key, value| stdout.puts "  #{key}=#{value}" }
        0
      end

      def run_capture_prompts(opts)
        stdout.puts "WARNING: enabling OTEL_LOG_USER_PROMPTS=1 will cause Claude Code"
        stdout.puts "to send your verbatim prompts (and the conversation history) to"
        stdout.puts "this dashboard's local SQLite. Type 'yes' to continue."
        stdout.print "> "
        answer = stdin.gets&.strip
        unless answer == "yes"
          stdout.puts "Aborted. No changes made."
          return 0
        end
        run_settings_change(opts) { |w| w.capture_prompts! }
      end

      def run_verify(opts)
        url = URI.parse("http://127.0.0.1:#{opts[:port]}/v1/metrics")
        body = JSON.generate(sample_metrics_envelope)
        response = post_json(url, body)
        if response.is_a?(Net::HTTPSuccess)
          stdout.puts "Verify OK: dashboard accepted the sample metrics envelope."
          0
        else
          failure("Verify failed: dashboard returned #{response&.code || "no response"}")
        end
      rescue Errno::ECONNREFUSED, SocketError => e
        failure("Verify failed: #{e.message}. Is the dashboard running on port #{opts[:port]}?")
      end

      def post_json(url, body)
        Net::HTTP.start(url.host, url.port, open_timeout: 2, read_timeout: 5) do |http|
          req = Net::HTTP::Post.new(url.path, "Content-Type" => "application/json")
          req.body = body
          http.request(req)
        end
      end

      # Smallest valid OTLP/HTTP/JSON metrics envelope — one counter point.
      # Used only for the --verify subcommand so users can confirm
      # end-to-end wiring without running a real claude session.
      def sample_metrics_envelope
        nano = (Time.now.to_f * 1_000_000_000).to_i.to_s
        {
          "resourceMetrics" => [{
            "resource" => {"attributes" => [
              {"key" => "service.name", "value" => {"stringValue" => "claude-memory-verify"}}
            ]},
            "scopeMetrics" => [{
              "scope" => {"name" => "claude-memory.verify"},
              "metrics" => [{
                "name" => "claude_memory.verify",
                "unit" => "count",
                "sum" => {
                  "dataPoints" => [{
                    "asInt" => "1",
                    "timeUnixNano" => nano,
                    "attributes" => []
                  }]
                }
              }]
            }]
          }]
        }
      end
    end
  end
end
