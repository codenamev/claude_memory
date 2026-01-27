# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Formats and reports check results
      class Reporter
        def initialize(stdout, stderr)
          @stdout = stdout
          @stderr = stderr
        end

        def report(results)
          @stdout.puts "Claude Memory Doctor\n"
          @stdout.puts "=" * 40

          # Report database checks with detailed output
          database_results = results.select { |r| r[:label] =~ /global|project/ }
          database_results.each do |result|
            @stdout.puts "\n## #{result[:label].capitalize} Database"
            report_result(result)
          end

          # Report other checks
          other_results = results.reject { |r| r[:label] =~ /global|project/ }
          other_results.each do |result|
            report_result(result)
          end

          @stdout.puts

          # Collect and report warnings
          warnings = results.flat_map { |r| (r[:warnings] || []).map { |w| "#{r[:label]}: #{w}" } }
          if warnings.any?
            @stdout.puts "Warnings:"
            warnings.each { |w| @stdout.puts "  ⚠ #{w}" }
            @stdout.puts
          end

          # Collect and report errors
          errors = results.select { |r| r[:status] == :error }
          if errors.any?
            @stdout.puts "Issues:"
            errors.each { |e| @stderr.puts "  ✗ #{e[:message]}" }
            errors.flat_map { |e| e[:errors] || [] }.each { |err| @stderr.puts "    • #{err}" }
            @stdout.puts
            @stdout.puts "Run 'claude-memory init' to set up."
            return false
          end

          @stdout.puts "All checks passed!"
          true
        end

        private

        def report_result(result)
          case result[:status]
          when :ok
            @stdout.puts status_line(result)
            report_details(result)
          when :warning
            @stdout.puts status_line(result)
            report_details(result)
          when :error
            # Errors are reported in summary
            report_details(result) if result[:details]&.any?
          end

          # Report fallback commands if available
          if result.dig(:details, :fallback_available)
            @stdout.puts "\n  Manual fallback available:"
            result.dig(:details, :fallback_commands)&.each do |cmd|
              @stdout.puts "    #{cmd}"
            end
          end
        end

        def status_line(result)
          case result[:status]
          when :ok
            "✓ #{result[:message]}"
          when :warning
            "⚠ #{result[:message]}"
          when :error
            "✗ #{result[:message]}"
          end
        end

        def report_details(result)
          details = result[:details] || {}
          return if details.empty?

          @stdout.puts "  Schema version: #{details[:schema_version]}" if details[:schema_version]
          @stdout.puts "  Facts: #{details[:fact_count]}" if details[:fact_count]
          @stdout.puts "  Content items: #{details[:content_count]}" if details[:content_count]
          @stdout.puts "  Open conflicts: #{details[:conflict_count]}" if details[:conflict_count]
          @stdout.puts "  Last ingest: #{details[:last_ingest]}" if details[:last_ingest]
          @stdout.puts "  Stuck operations: #{details[:stuck_operations]}" if details.key?(:stuck_operations)

          if details.key?(:schema_valid)
            health = details[:schema_valid] ? "healthy" : "issues detected"
            @stdout.puts "  Schema health: #{health}"
          end
        end
      end
    end
  end
end
