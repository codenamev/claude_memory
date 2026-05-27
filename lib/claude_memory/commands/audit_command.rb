# frozen_string_literal: true

require "json"
require "optparse"

module ClaudeMemory
  module Commands
    # Runs the memory health audit and prints findings. Exits non-zero
    # when error-severity findings are present (unless --no-exit is
    # given). JSON output is the stable surface — humans should not
    # script against the text output.
    class AuditCommand < BaseCommand
      SEVERITY_RANK = {info: 0, warn: 1, error: 2}.freeze

      def call(args)
        opts = parse_opts(args)
        return 1 if opts.nil?

        manager = Store::StoreManager.new
        result = Audit::Runner.new(manager: manager).run
        filtered = filter_by_severity(result.findings, opts[:severity])

        if opts[:json]
          stdout.puts JSON.pretty_generate(payload(result, filtered))
        else
          render_text(result, filtered)
        end

        manager.close
        opts[:no_exit] ? 0 : result.exit_code
      end

      def filter_by_severity(findings, threshold)
        return findings if threshold.nil?
        floor = SEVERITY_RANK.fetch(threshold) { return findings }
        findings.select { |f| SEVERITY_RANK[f.severity] >= floor }
      end

      private

      def parse_opts(args)
        options = {json: false, no_exit: false, severity: nil}
        parser = OptionParser.new do |o|
          o.banner = "Usage: claude-memory audit [--json] [--no-exit] [--severity=error|warn|info]"
          o.on("--json", "Emit JSON instead of text") { options[:json] = true }
          o.on("--no-exit", "Always exit 0 even on error-severity findings") { options[:no_exit] = true }
          o.on("--severity LEVEL", "Only show findings at or above LEVEL (error|warn|info)") { |v| options[:severity] = v.to_sym }
        end
        parser.parse!(args.dup)
        options
      rescue OptionParser::InvalidOption => e
        stderr.puts e.message
        nil
      end

      def payload(result, filtered)
        {
          ok: result.ok?,
          checks_run: result.stats[:checks_run],
          counts: {
            error: result.errors.size,
            warn: result.warnings.size,
            info: result.info.size
          },
          stats: result.stats.except(:checks_run),
          findings: filtered.map(&:to_h)
        }
      end

      def render_text(result, filtered)
        stdout.puts "Memory health audit — #{Time.now.utc.iso8601}"
        stdout.puts("=" * 60)
        render_stats(result.stats)
        stdout.puts ""
        render_summary(result)
        stdout.puts ""
        render_findings(filtered)
        stdout.puts ""
        stdout.puts(result.ok? ? "OK" : "FAIL")
      end

      def render_stats(stats)
        %i[global project].each do |scope|
          s = stats[scope]
          next unless s
          preds = s[:predicate_counts].map { |k, v| "#{k}=#{v}" }.join(", ")
          stdout.puts "#{scope.to_s.capitalize.ljust(7)} #{s[:active_facts]} active facts  #{preds}"
        end
      end

      def render_summary(result)
        stdout.puts "Checks run: #{result.stats[:checks_run]}"
        stdout.puts "Errors: #{result.errors.size}   Warnings: #{result.warnings.size}   Info: #{result.info.size}"
      end

      def render_findings(findings)
        if findings.empty?
          stdout.puts "No findings."
          return
        end

        findings.each do |f|
          marker = case f.severity
          when :error then "[ERROR]"
          when :warn then "[WARN]"
          when :info then "[INFO]"
          end
          stdout.puts "#{marker} #{f.id}  #{f.title}"
          stdout.puts "  #{f.detail}"
          stdout.puts "  → #{f.suggestion}"
          stdout.puts "  fact_ids: #{f.fact_ids.first(20).inspect}#{"  (+#{f.fact_ids.size - 20} more)" if f.fact_ids.size > 20}" if f.fact_ids.any?
          stdout.puts ""
        end
      end
    end
  end
end
