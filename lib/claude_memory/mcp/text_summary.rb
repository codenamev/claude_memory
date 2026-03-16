# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Generates human-readable text summaries from MCP tool results.
    # Used alongside structuredContent for dual content/structuredContent pattern.
    module TextSummary
      def self.for_tool(name, result)
        return result[:error] if result[:error]

        case name
        when "memory.recall" then summarize_recall(result)
        when "memory.recall_index" then summarize_recall_index(result)
        when "memory.recall_details" then summarize_recall_details(result)
        when "memory.explain" then summarize_explain(result)
        when "memory.changes" then summarize_changes(result)
        when "memory.conflicts" then summarize_conflicts(result)
        when "memory.sweep_now" then summarize_sweep(result)
        when "memory.status" then summarize_status(result)
        when "memory.stats" then summarize_stats(result)
        when "memory.promote" then summarize_promote(result)
        when "memory.store_extraction" then summarize_extraction(result)
        when "memory.decisions" then summarize_shortcut(result)
        when "memory.conventions" then summarize_shortcut(result)
        when "memory.architecture" then summarize_shortcut(result)
        when "memory.facts_by_tool" then summarize_tool_facts(result)
        when "memory.facts_by_context" then summarize_context_facts(result)
        when "memory.recall_semantic" then summarize_semantic(result)
        when "memory.search_concepts" then summarize_concepts(result)
        when "memory.fact_graph" then summarize_fact_graph(result)
        when "memory.check_setup" then summarize_check_setup(result)
        else JSON.generate(result)
        end
      end

      def self.summarize_recall(result)
        facts = result[:facts] || []
        return "No facts found." if facts.empty?

        lines = ["Found #{facts.size} fact(s):"]
        facts.each do |f|
          lines << "- [#{fact_label(f)}] #{f[:subject]}.#{f[:predicate]} = #{f[:object]}"
        end
        lines.join("\n")
      end

      def self.summarize_recall_index(result)
        facts = result[:facts] || []
        return "No matching facts for '#{result[:query]}'." if facts.empty?

        lines = ["#{result[:result_count]} fact(s) matching '#{result[:query]}' (~#{result[:total_estimated_tokens]} tokens):"]
        facts.each do |f|
          lines << "- [#{fact_label(f)}] #{f[:subject]}.#{f[:predicate]}: #{f[:object_preview]} (#{f[:tokens]}t)"
        end
        lines.join("\n")
      end

      def self.summarize_recall_details(result)
        facts = result[:facts] || []
        return "No facts found for given IDs." if facts.empty?

        lines = ["#{result[:fact_count]} fact(s):"]
        facts.each do |f|
          fact = f[:fact]
          lines << "- [#{fact_label(fact)}] #{fact[:subject]}.#{fact[:predicate]} = #{fact[:object]} (#{fact[:status]}, #{fact[:scope]})"
        end
        lines.join("\n")
      end

      def self.summarize_explain(result)
        f = result[:fact]
        lines = ["Fact [#{fact_label(f)}]: #{f[:subject]}.#{f[:predicate]} = #{f[:object]}"]
        lines << "Status: #{f[:status]}, valid from: #{f[:valid_from_ago] || f[:valid_from] || "unknown"}"
        lines << "Source: #{result[:source]}"

        receipts = result[:receipts] || []
        if receipts.any?
          lines << "Evidence: #{receipts.map { |r| r[:quote] }.join("; ")}"
        end

        lines.join("\n")
      end

      def self.summarize_changes(result)
        changes = result[:changes] || []
        return "No changes since #{result[:since]}." if changes.empty?

        lines = ["#{changes.size} change(s) since #{result[:since]}:"]
        changes.each do |c|
          ago = c[:created_ago] ? " (#{c[:created_ago]})" : ""
          lines << "- [#{fact_label(c)}] #{c[:predicate]}: #{c[:object]} [#{c[:status]}]#{ago}"
        end
        lines.join("\n")
      end

      def self.summarize_conflicts(result)
        return "No open conflicts." if result[:count] == 0

        lines = ["#{result[:count]} conflict(s):"]
        (result[:conflicts] || []).each do |c|
          lines << "- Conflict ##{c[:id]}: fact #{c[:fact_a]} vs fact #{c[:fact_b]} (#{c[:status]})"
        end
        lines.join("\n")
      end

      def self.summarize_sweep(result)
        escalation = result[:escalation_level] ? " [#{result[:escalation_level]}]" : ""
        "Sweep (#{result[:scope]})#{escalation}: #{result[:proposed_expired]} proposed expired, " \
          "#{result[:disputed_expired]} disputed expired, " \
          "#{result[:orphaned_deleted]} orphaned deleted, " \
          "#{result[:content_pruned]} content pruned " \
          "(#{result[:elapsed_seconds]}s)"
      end

      def self.summarize_status(result)
        dbs = result[:databases] || {}
        lines = ["Memory status:"]
        dbs.each do |name, info|
          lines << if info[:exists] == false
            "- #{name}: not initialized"
          else
            "- #{name}: #{info[:facts_active]} active facts, #{info[:open_conflicts]} conflicts (schema v#{info[:schema_version]})"
          end
        end
        lines.join("\n")
      end

      def self.summarize_stats(result)
        dbs = result[:databases] || {}
        lines = ["Stats (scope: #{result[:scope]}):"]
        dbs.each do |name, info|
          if info[:exists] == false
            lines << "- #{name}: not initialized"
          else
            facts = info[:facts] || {}
            lines << "- #{name}: #{facts[:active]}/#{facts[:total]} active facts, #{info[:entities]&.dig(:total) || 0} entities"
          end
        end
        lines.join("\n")
      end

      def self.summarize_promote(result)
        if result[:success]
          "Fact #{result[:project_fact_id]} promoted to global (new ID: #{result[:global_fact_id]})"
        else
          result[:error]
        end
      end

      def self.summarize_extraction(result)
        if result[:success]
          "Stored: #{result[:facts_created]} facts, #{result[:entities_created]} entities, " \
            "#{result[:facts_superseded]} superseded, #{result[:conflicts_created]} conflicts"
        else
          result[:error]
        end
      end

      def self.summarize_shortcut(result)
        facts = result[:facts] || []
        return "No #{result[:category]} found." if facts.empty?

        lines = ["#{result[:count]} #{result[:category]}:"]
        facts.each do |f|
          lines << "- [#{fact_label(f)}] #{f[:object]}"
        end
        lines.join("\n")
      end

      def self.summarize_tool_facts(result)
        facts = result[:facts] || []
        return "No facts discovered via #{result[:tool_name]}." if facts.empty?

        lines = ["#{result[:count]} fact(s) from #{result[:tool_name]}:"]
        facts.each do |f|
          lines << "- [#{fact_label(f)}] #{f[:subject]}.#{f[:predicate]} = #{f[:object]}"
        end
        lines.join("\n")
      end

      def self.summarize_context_facts(result)
        facts = result[:facts] || []
        return "No facts for #{result[:context_type]}=#{result[:context_value]}." if facts.empty?

        lines = ["#{result[:count]} fact(s) for #{result[:context_type]}=#{result[:context_value]}:"]
        facts.each do |f|
          lines << "- [#{fact_label(f)}] #{f[:subject]}.#{f[:predicate]} = #{f[:object]}"
        end
        lines.join("\n")
      end

      def self.summarize_semantic(result)
        facts = result[:facts] || []
        return "No semantic matches for '#{result[:query]}'." if facts.empty?

        lines = ["#{result[:count]} match(es) for '#{result[:query]}' (#{result[:mode]}):"]
        facts.each do |f|
          sim = f[:similarity] ? " (#{(f[:similarity] * 100).round}%)" : ""
          lines << "- [#{fact_label(f)}] #{f[:subject]}.#{f[:predicate]} = #{f[:object]}#{sim}"
        end
        lines.join("\n")
      end

      def self.summarize_concepts(result)
        facts = result[:facts] || []
        concepts_str = (result[:concepts] || []).join(" + ")
        return "No facts matching all concepts: #{concepts_str}." if facts.empty?

        lines = ["#{result[:count]} fact(s) matching #{concepts_str}:"]
        facts.each do |f|
          sim = f[:average_similarity] ? " (#{(f[:average_similarity] * 100).round}%)" : ""
          lines << "- [#{fact_label(f)}] #{f[:subject]}.#{f[:predicate]} = #{f[:object]}#{sim}"
        end
        lines.join("\n")
      end

      def self.summarize_fact_graph(result)
        nodes = result[:nodes] || []
        edges = result[:edges] || []
        return "Fact #{result[:root_fact_id]} not found." if nodes.empty?

        lines = ["Graph for fact ##{result[:root_fact_id]} (depth #{result[:depth]}): #{result[:node_count]} nodes, #{result[:edge_count]} edges"]
        nodes.each do |n|
          label = n[:docid] || n[:id]
          lines << "- [#{label}] #{n[:subject]}.#{n[:predicate]} = #{n[:object]} (#{n[:status]})"
        end
        if edges.any?
          lines << "Edges:"
          edges.each do |e|
            lines << "  #{e[:from]} --#{e[:type]}--> #{e[:to]}"
          end
        end
        lines.join("\n")
      end

      def self.summarize_check_setup(result)
        lines = ["Setup status: #{result[:status]}"]
        lines << "Version: #{result[:version][:current]} (latest: #{result[:version][:latest]})"

        components = result[:components] || {}
        lines << "Components: global_db=#{components[:global_database]}, project_db=#{components[:project_database]}, hooks=#{components[:hooks_configured]}"

        issues = result[:issues] || []
        issues.each { |i| lines << "Issue: #{i}" }

        warnings = result[:warnings] || []
        warnings.each { |w| lines << "Warning: #{w}" }

        lines.join("\n")
      end

      # Format fact identifier: prefer docid if available, fall back to integer id
      def self.fact_label(fact)
        fact[:docid] || fact[:id]
      end
    end
  end
end
