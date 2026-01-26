# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Displays detailed statistics about the memory system
    # Shows facts by status and predicate, entities by type, content items,
    # provenance coverage, conflicts, and database sizes
    class StatsCommand < BaseCommand
      SCOPE_ALL = "all"
      SCOPE_GLOBAL = "global"
      SCOPE_PROJECT = "project"

      def call(args)
        opts = parse_options(args, {scope: SCOPE_ALL}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory stats [options]"
            parser.on("--scope SCOPE", ["all", "global", "project"],
              "Show stats for: all (default), global, or project") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new

        stdout.puts "ClaudeMemory Statistics"
        stdout.puts "=" * 50
        stdout.puts

        if opts[:scope] == SCOPE_ALL || opts[:scope] == SCOPE_GLOBAL
          print_database_stats("GLOBAL", manager.global_db_path)
        end

        if opts[:scope] == SCOPE_ALL || opts[:scope] == SCOPE_PROJECT
          print_database_stats("PROJECT", manager.project_db_path)
        end

        manager.close
        0
      end

      private

      def print_database_stats(label, db_path)
        stdout.puts "## #{label} DATABASE"
        stdout.puts

        unless File.exist?(db_path)
          stdout.puts "Database does not exist: #{db_path}"
          stdout.puts
          return
        end

        begin
          db = Sequel.sqlite(db_path, readonly: true)

          # Facts statistics
          print_fact_stats(db)
          stdout.puts

          # Entities statistics
          print_entity_stats(db)
          stdout.puts

          # Content items statistics
          print_content_stats(db)
          stdout.puts

          # Provenance coverage
          print_provenance_stats(db)
          stdout.puts

          # Conflicts
          print_conflict_stats(db)
          stdout.puts

          # ROI Metrics (if available)
          print_roi_metrics(db)
          stdout.puts

          # Database size
          print_database_size(db_path)
          stdout.puts

          db.disconnect
        rescue => e
          stderr.puts "Error reading database: #{e.message}"
        end
      end

      def print_fact_stats(db)
        total = db[:facts].count
        active = db[:facts].where(status: "active").count
        superseded = db[:facts].where(status: "superseded").count

        stdout.puts "Facts:"
        stdout.puts "  Total: #{total} (#{active} active, #{superseded} superseded)"

        if total > 0
          stdout.puts
          stdout.puts "  Top Predicates:"

          predicate_counts = db[:facts]
            .where(status: "active")
            .group_and_count(:predicate)
            .order(Sequel.desc(:count))
            .limit(10)
            .all

          predicate_counts.each do |row|
            stdout.puts "    #{row[:count].to_s.rjust(4)} - #{row[:predicate]}"
          end
        end
      end

      def print_entity_stats(db)
        total = db[:entities].count

        stdout.puts "Entities: #{total}"

        if total > 0
          type_counts = db[:entities]
            .group_and_count(:type)
            .order(Sequel.desc(:count))
            .all

          type_counts.each do |row|
            stdout.puts "  #{row[:count].to_s.rjust(4)} - #{row[:type]}"
          end
        end
      end

      def print_content_stats(db)
        total = db[:content_items].count

        stdout.puts "Content Items: #{total}"

        if total > 0
          first_date = db[:content_items].min(:occurred_at)
          last_date = db[:content_items].max(:occurred_at)

          if first_date && last_date
            first_formatted = format_date(first_date)
            last_formatted = format_date(last_date)
            stdout.puts "  Date Range: #{first_formatted} - #{last_formatted}"
          end
        end
      end

      def print_provenance_stats(db)
        total_active_facts = db[:facts].where(status: "active").count
        facts_with_provenance = db[:provenance]
          .join(:facts, id: :fact_id)
          .where(Sequel[:facts][:status] => "active")
          .select(Sequel[:provenance][:fact_id])
          .distinct
          .count

        if total_active_facts > 0
          percentage = (facts_with_provenance * 100.0 / total_active_facts).round(1)
          stdout.puts "Provenance: #{facts_with_provenance}/#{total_active_facts} facts have sources (#{percentage}%)"
        else
          stdout.puts "Provenance: 0/0 facts have sources"
        end
      end

      def print_conflict_stats(db)
        open = db[:conflicts].where(status: "open").count
        resolved = db[:conflicts].where(status: "resolved").count
        total = open + resolved

        stdout.puts "Conflicts: #{open} open, #{resolved} resolved (#{total} total)"
      end

      def print_roi_metrics(db)
        # Check if ingestion_metrics table exists (schema v7+)
        return unless db.table_exists?(:ingestion_metrics)

        # standard:disable Performance/Detect (Sequel DSL requires .select{}.first)
        result = db[:ingestion_metrics]
          .select {
            [
              sum(:input_tokens).as(:total_input),
              sum(:output_tokens).as(:total_output),
              sum(:facts_extracted).as(:total_facts),
              count(:id).as(:total_ops)
            ]
          }
          .first
        # standard:enable Performance/Detect

        return if result.nil? || result[:total_ops].to_i.zero?

        total_input = result[:total_input].to_i
        total_output = result[:total_output].to_i
        total_facts = result[:total_facts].to_i
        total_ops = result[:total_ops].to_i

        efficiency = total_input.zero? ? 0.0 : (total_facts.to_f / total_input * 1000).round(2)

        stdout.puts "Token Economics (Distillation ROI):"
        stdout.puts "  Input Tokens: #{format_number(total_input)}"
        stdout.puts "  Output Tokens: #{format_number(total_output)}"
        stdout.puts "  Facts Extracted: #{format_number(total_facts)}"
        stdout.puts "  Operations: #{format_number(total_ops)}"
        stdout.puts "  Efficiency: #{efficiency} facts per 1,000 input tokens"
      end

      def print_database_size(db_path)
        size_bytes = File.size(db_path)
        size_kb = (size_bytes / 1024.0).round(1)
        size_mb = (size_bytes / (1024.0 * 1024.0)).round(2)

        if size_mb >= 1.0
          stdout.puts "Database Size: #{size_mb} MB"
        else
          stdout.puts "Database Size: #{size_kb} KB"
        end
      end

      def format_date(iso8601_string)
        # Extract just the date part (YYYY-MM-DD) from ISO8601 timestamp
        return iso8601_string unless iso8601_string

        date_part = iso8601_string.split("T").first
        return date_part if date_part

        # Fallback to first 10 chars
        iso8601_string[0...10]
      end

      def format_number(num)
        # Format number with comma separators (e.g., 1234567 => "1,234,567")
        num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end
    end
  end
end
