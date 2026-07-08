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
        opts = parse_options(args, {scope: SCOPE_ALL, tools: false, tokens: false, stale: false, observations: false, since_days: nil, stale_days: nil}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory stats [options]"
            parser.on("--scope SCOPE", ["all", "global", "project"],
              "Show stats for: all (default), global, or project") { |v| o[:scope] = v }
            parser.on("--tools", "Show MCP tool-call usage stats") { o[:tools] = true }
            parser.on("--tokens", "Show SessionStart context-injection token budget") { o[:tokens] = true }
            parser.on("--stale", "Show facts not recalled in CLAUDE_MEMORY_STALE_DAYS (default 14)") { o[:stale] = true }
            parser.on("--observations", "Show episodic observation counts (status, kind, promotable)") { o[:observations] = true }
            parser.on("--since DAYS", Integer, "Limit --tools/--tokens to last N days") { |v| o[:since_days] = v }
            parser.on("--stale-days N", Integer, "Override staleness threshold for --stale") { |v| o[:stale_days] = v }
          end
        end
        return 1 if opts.nil?

        if opts[:tools]
          return print_mcp_tool_call_stats(opts[:since_days])
        end

        if opts[:observations]
          return print_observation_stats
        end

        if opts[:tokens]
          return print_token_budget_stats(opts[:since_days])
        end

        if opts[:stale]
          return print_stale_facts(opts[:stale_days])
        end

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

      def print_stale_facts(override_days)
        threshold = override_days || ClaudeMemory::Configuration.new.stale_days
        manager = ClaudeMemory::Store::StoreManager.new
        result = ClaudeMemory::Recall::StaleDetector.stale_facts(manager, threshold_days: threshold)

        stdout.puts "Stale facts (last_recalled_at older than #{threshold} day#{"s" unless threshold == 1})"
        stdout.puts "=" * 60

        if result[:total].zero?
          stdout.puts "No stale facts."
          stdout.puts ""
          stdout.puts "Run `claude-memory sweep` to refresh last_recalled_at from activity_events."
        else
          stdout.puts "Total: #{result[:total]} (project=#{result[:project].size}, global=#{result[:global].size})"
          stdout.puts ""
          %i[project global].each do |scope|
            rows = result[scope]
            next if rows.empty?
            stdout.puts "## #{scope.to_s.upcase}"
            rows.each do |row|
              last = row[:last_recalled_at] || "never"
              stdout.puts "  ##{row[:id]} [#{row[:predicate]}] #{row[:object_literal]&.slice(0, 80)} (last: #{last})"
            end
            stdout.puts ""
          end
        end

        manager.close
        0
      end

      def print_observation_stats
        manager = ClaudeMemory::Store::StoreManager.new
        stores = %w[project global]
          .filter_map { |scope| manager.store_if_exists(scope) }
          .select { |store| store.db.table_exists?(:observations) }

        stdout.puts "Observation Statistics (episodic layer)"
        stdout.puts "=" * 50

        threshold = ClaudeMemory::Domain::Observation::PROMOTION_THRESHOLD

        total = stores.sum { |s| s.observations.count }
        if total.zero?
          stdout.puts "No observations recorded yet."
          manager.close
          return 0
        end

        active = stores.sum { |s| s.observations.where(status: "active").count }
        consolidated = stores.sum { |s| s.observations.where(status: "consolidated").count }
        expired = stores.sum { |s| s.observations.where(status: "expired").count }
        promoted = stores.sum { |s| s.observations.exclude(promoted_at: nil).count }
        promotable = stores.sum do |s|
          s.observations.where(status: "active", promoted_at: nil)
            .where { corroboration_count >= threshold }.count
        end

        stdout.puts "Active: #{active}"
        stdout.puts "Consolidated: #{consolidated}"
        stdout.puts "Expired: #{expired}"
        stdout.puts "Promoted: #{promoted}"
        stdout.puts "Promotable (>= #{threshold} sightings): #{promotable}"
        stdout.puts

        kinds = Hash.new(0)
        stores.each do |store|
          store.observations.where(status: "active").group_and_count(:kind).each do |row|
            kinds[row[:kind]] += row[:count]
          end
        end

        stdout.puts "By kind (active):"
        if kinds.empty?
          stdout.puts "  (none)"
        else
          kinds.sort_by { |_k, v| -v }.each do |kind, count|
            stdout.puts "  #{count.to_s.rjust(4)} - #{kind}"
          end
        end

        manager.close
        0
      end

      def open_readonly(db_path)
        Sequel.connect("extralite://#{db_path}")
      end

      def print_database_stats(label, db_path)
        stdout.puts "## #{label} DATABASE"
        stdout.puts

        unless File.exist?(db_path)
          stdout.puts "Database does not exist: #{db_path}"
          stdout.puts
          return
        end

        begin
          db = open_readonly(db_path)

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

          # Database size + optimization hints
          print_database_size(db_path)
          check_fts_format(db)
          stdout.puts

          db.disconnect
        rescue Sequel::DatabaseError, Extralite::Error => e
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

      def check_fts_format(db)
        fts_sql = db.fetch("SELECT sql FROM sqlite_master WHERE name = 'content_fts' AND type = 'table'").first
        return unless fts_sql && !fts_sql[:sql].to_s.include?("content=''")

        stdout.puts "  Optimization available: FTS index stores duplicate text."
        stdout.puts "  Run 'claude-memory compact' to reduce size by ~40%."
      rescue
        # Ignore errors reading FTS metadata
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

      def print_mcp_tool_call_stats(since_days)
        manager = ClaudeMemory::Store::StoreManager.new
        db_path = manager.project_db_path

        stdout.puts "MCP Tool Call Statistics"
        stdout.puts "=" * 50

        unless File.exist?(db_path)
          stdout.puts "Project database does not exist: #{db_path}"
          manager.close
          return 0
        end

        db = open_readonly(db_path)

        unless db.table_exists?(:mcp_tool_calls)
          stdout.puts "No telemetry recorded yet (run MCP server first)."
          db.disconnect
          manager.close
          return 0
        end

        dataset = db[:mcp_tool_calls]
        if since_days
          cutoff = (Time.now - since_days * 86400).utc.iso8601
          dataset = dataset.where { called_at >= cutoff }
          stdout.puts "Window: last #{since_days} day#{"s" unless since_days == 1}"
        else
          stdout.puts "Window: all time"
        end
        stdout.puts

        total = dataset.count
        if total.zero?
          stdout.puts "No tool calls recorded in window."
          db.disconnect
          manager.close
          return 0
        end

        errors = dataset.exclude(error_class: nil).count
        error_rate = (errors * 100.0 / total).round(1)
        stdout.puts "Total calls: #{format_number(total)}"
        stdout.puts "Errors: #{format_number(errors)} (#{error_rate}%)"
        stdout.puts

        print_per_tool_breakdown(dataset)

        db.disconnect
        manager.close
        0
      rescue Sequel::DatabaseError, Extralite::Error => e
        stderr.puts "Error reading telemetry: #{e.message}"
        1
      end

      TOKEN_BUCKETS = [
        ["<500", 0, 500],
        ["500-1000", 500, 1000],
        ["1000-2000", 1000, 2000],
        ["2000-5000", 2000, 5000],
        ["5000+", 5000, Float::INFINITY]
      ].freeze

      def print_token_budget_stats(since_days)
        manager = ClaudeMemory::Store::StoreManager.new
        db_path = manager.project_db_path

        stdout.puts "SessionStart Context Token Budget"
        stdout.puts "=" * 50

        unless File.exist?(db_path)
          stdout.puts "Project database does not exist: #{db_path}"
          manager.close
          return 0
        end

        db = open_readonly(db_path)

        unless db.table_exists?(:activity_events)
          stdout.puts "No activity telemetry recorded yet."
          db.disconnect
          manager.close
          return 0
        end

        dataset = db[:activity_events]
          .where(event_type: "hook_context", status: "success")
        if since_days
          cutoff = (Time.now - since_days * 86400).utc.iso8601
          dataset = dataset.where { occurred_at >= cutoff }
          stdout.puts "Window: last #{since_days} day#{"s" unless since_days == 1}"
        else
          stdout.puts "Window: all time"
        end
        stdout.puts

        tokens = dataset.select_map(:detail_json).filter_map do |json|
          next unless json
          value = JSON.parse(json)["context_tokens"]
          value if value.is_a?(Integer) && value > 0
        end

        if tokens.empty?
          stdout.puts "No context injections recorded in window."
          stdout.puts ""
          stdout.puts "Token telemetry is recorded automatically on SessionStart hooks."
          stdout.puts "Run a Claude Code session in this project to populate."
          db.disconnect
          manager.close
          return 0
        end

        sorted = tokens.sort
        total = sorted.size
        stdout.puts "Sessions: #{format_number(total)}"
        stdout.puts "p50: #{format_number(Core::Percentile.of(sorted, 0.50))} tokens"
        stdout.puts "p95: #{format_number(Core::Percentile.of(sorted, 0.95))} tokens"
        stdout.puts "Avg: #{format_number((sorted.sum.to_f / total).round)} tokens"
        stdout.puts "Min: #{format_number(sorted.first)} tokens"
        stdout.puts "Max: #{format_number(sorted.last)} tokens"
        stdout.puts ""
        print_token_distribution(sorted)

        db.disconnect
        manager.close
        0
      rescue Sequel::DatabaseError, JSON::ParserError, Extralite::Error => e
        stderr.puts "Error reading token telemetry: #{e.message}"
        1
      end

      def print_token_distribution(sorted)
        total = sorted.size
        stdout.puts "Distribution:"
        TOKEN_BUCKETS.each do |label, low, high|
          count = sorted.count { |t| t >= low && t < high }
          pct = (count * 100.0 / total).round(1)
          bar = "█" * (pct / 5).round
          stdout.puts "  #{label.ljust(12)} #{count.to_s.rjust(5)} (#{pct.to_s.rjust(5)}%) #{bar}"
        end
      end

      def print_per_tool_breakdown(dataset)
        stdout.puts "Per-tool breakdown:"
        stdout.puts "  #{"Tool".ljust(28)} #{"Calls".rjust(7)}  #{"Avg ms".rjust(8)}  #{"P95 ms".rjust(8)}  #{"Err %".rjust(6)}"

        rows = dataset
          .group_and_count(:tool_name)
          .order(Sequel.desc(:count))
          .all

        rows.each do |row|
          tool = row[:tool_name]
          calls = row[:count]
          durations = dataset.where(tool_name: tool).select_map(:duration_ms).sort
          avg = (durations.sum.to_f / calls).round(1)
          p95 = Core::Percentile.of(durations, 0.95)
          tool_errors = dataset.where(tool_name: tool).exclude(error_class: nil).count
          tool_err_rate = (tool_errors * 100.0 / calls).round(1)

          stdout.puts "  #{tool.to_s.ljust(28)} #{calls.to_s.rjust(7)}  #{avg.to_s.rjust(8)}  #{p95.to_s.rjust(8)}  #{tool_err_rate.to_s.rjust(6)}"
        end
      end
    end
  end
end
