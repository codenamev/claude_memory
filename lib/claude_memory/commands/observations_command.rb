# frozen_string_literal: true

require "optparse"
require "json"

module ClaudeMemory
  module Commands
    # CLI parity for the episodic observation layer — the "what happened" log
    # that complements the semantic fact store ("what is true").
    #
    # Subcommands:
    #   observations [list]   Summary: counts by status/kind/priority,
    #                         corroboration + promotion readiness, compression
    #                         ratio, and a recent timeline.
    #   observations promote <id> --predicate P --object O [--subject S] [--scope ...]
    #   observations consolidate <id1,id2,...> --body "<synthesis>" [--scope ...]
    #
    # The promote subcommand reuses the same corroboration gate and Resolver
    # path as the memory.promote_observation MCP tool, so the anti-hallucination
    # threshold is enforced identically across surfaces.
    class ObservationsCommand < BaseCommand
      def call(args)
        subcommand = args.first
        case subcommand
        when "promote"
          promote(args.drop(1))
        when "consolidate"
          consolidate(args.drop(1))
        when "list", nil
          list(args.drop(subcommand ? 1 : 0))
        else
          # Treat unknown first token as options to `list` (e.g. --json).
          list(args)
        end
      end

      private

      # --- list (default) -----------------------------------------------------

      def list(args)
        opts = parse_options(args, {limit: 20, kind: nil, status: "active", scope: nil, json: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory observations [list] [options]"
            parser.on("--limit N", Integer, "Max rows in the recent timeline (default: 20)") { |v| o[:limit] = v }
            parser.on("--kind K", "Filter timeline by kind (e.g. decision, preference, event)") { |v| o[:kind] = v }
            parser.on("--status S", "Filter timeline by status (active, consolidated, expired)") { |v| o[:status] = v }
            parser.on("--scope SCOPE", %w[project global], "Limit to a single scope") { |v| o[:scope] = v }
            parser.on("--json", "Emit machine-readable JSON") { o[:json] = true }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        stores = observation_stores(manager, opts[:scope])

        report = build_report(stores, opts)
        manager.close

        if opts[:json]
          stdout.puts(JSON.pretty_generate(report))
        else
          render_report(report)
        end
        0
      end

      def build_report(stores, opts)
        stats = Observe::ObservationStats.new(stores)
        {
          totals: stats.totals,
          by_kind: stats.by_field(:kind),
          by_priority: stats.by_field(:priority),
          corroboration: stats.corroboration,
          compression: stats.compression,
          recent: recent(stores, opts)
        }
      end

      def render_report(report)
        stdout.puts "Observations (episodic 'what happened' log)"
        stdout.puts "=" * 50
        stdout.puts

        render_totals(report[:totals])
        stdout.puts
        render_breakdown("By kind (active)", report[:by_kind])
        stdout.puts
        render_priority(report[:by_priority])
        stdout.puts
        render_corroboration(report[:corroboration])
        stdout.puts
        render_compression(report[:compression])
        stdout.puts
        render_recent(report[:recent])
      end

      def render_totals(totals)
        stdout.puts "Totals:"
        stdout.puts "  Active: #{totals[:active]}"
        stdout.puts "  Consolidated: #{totals[:consolidated]}"
        stdout.puts "  Expired: #{totals[:expired]}"
        stdout.puts "  Promoted: #{totals[:promoted]}"
      end

      def render_breakdown(title, counts)
        stdout.puts "#{title}:"
        if counts.empty?
          stdout.puts "  (none)"
          return
        end
        counts.sort_by { |_k, v| -v }.each do |key, count|
          stdout.puts "  #{count.to_s.rjust(4)} - #{key}"
        end
      end

      def render_priority(counts)
        stdout.puts "By priority (active):"
        if counts.empty?
          stdout.puts "  (none)"
          return
        end
        counts.sort_by { |priority, _v| priority }.each do |priority, count|
          stdout.puts "  #{count.to_s.rjust(4)} - #{priority} (#{priority_label(priority)})"
        end
      end

      def priority_label(priority)
        case priority
        when Domain::Observation::IMPORTANT then "important"
        when Domain::Observation::MAYBE then "maybe"
        else "info"
        end
      end

      def render_corroboration(corroboration)
        threshold = Domain::Observation::PROMOTION_THRESHOLD
        stdout.puts "Corroboration:"
        stdout.puts "  Max sightings: #{corroboration[:max]}"
        stdout.puts "  Promotable (>= #{threshold} sightings, not yet promoted): #{corroboration[:promotable]}"
      end

      def render_compression(compression)
        ratio = compression[:ratio]
        stdout.puts "Compression:"
        stdout.puts "  Observation tokens: #{compression[:observation_tokens]}"
        stdout.puts "  Source tokens: #{compression[:source_tokens]}"
        if ratio
          stdout.puts "  Ratio (source / observation): #{ratio}x"
        else
          stdout.puts "  Ratio (source / observation): n/a"
        end
      end

      def render_recent(recent)
        stdout.puts "Recent timeline:"
        if recent.empty?
          stdout.puts "  (no observations)"
          return
        end
        recent.each do |obs|
          marker = priority_marker(obs[:priority])
          stdout.puts "  ##{obs[:id]} #{marker} [#{obs[:kind]}] x#{obs[:corroboration_count]} (#{obs[:observed_ago]})"
          stdout.puts "    #{obs[:body]}"
        end
      end

      def priority_marker(priority)
        case priority
        when Domain::Observation::IMPORTANT then "[!]"
        when Domain::Observation::MAYBE then "[~]"
        else "[ ]"
        end
      end

      # --- read aggregation (mirrors Dashboard::Observations) -----------------

      def observation_stores(manager, scope)
        scopes = scope ? [scope] : %w[project global]
        scopes.filter_map { |s| manager.store_if_exists(s) }
          .select { |store| store.db.table_exists?(:observations) }
      end

      def recent(stores, opts)
        rows = stores.flat_map do |store|
          dataset = store.observations
          dataset = dataset.where(status: opts[:status]) if opts[:status]
          dataset = dataset.where(kind: opts[:kind]) if opts[:kind]
          dataset.order(Sequel.desc(:observed_at), Sequel.desc(:id)).limit(opts[:limit]).all
        end

        rows.sort_by { |o| o[:observed_at].to_s }.reverse.first(opts[:limit]).map do |o|
          {
            id: o[:id], kind: o[:kind], priority: o[:priority],
            corroboration_count: o[:corroboration_count], body: o[:body],
            observed_ago: Core::RelativeTime.format(o[:observed_at])
          }
        end
      end

      # --- promote ------------------------------------------------------------

      def promote(args)
        opts = parse_options(args, {predicate: nil, object: nil, subject: "repo", scope: "project"}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory observations promote <id> --predicate P --object O [options]"
            parser.on("--predicate P", "Fact predicate (e.g. decision, convention)") { |v| o[:predicate] = v }
            parser.on("--object O", "Fact object (the claim text)") { |v| o[:object] = v }
            parser.on("--subject S", "Fact subject (default: repo)") { |v| o[:subject] = v }
            parser.on("--scope SCOPE", %w[project global], "Database scope (default: project)") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        observation_id = parse_id(args.first)
        return failure("Usage: claude-memory observations promote <id> --predicate P --object O") if observation_id.nil?
        return failure("--predicate and --object are required") if opts[:predicate].nil? || opts[:object].to_s.strip.empty?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])

        result = promote_observation(store, observation_id, opts)
        manager.close

        return failure(result[:error]) if result[:error]

        stdout.puts "Promoted observation ##{observation_id} -> fact ##{result[:fact_id]}"
        stdout.puts "  #{result[:predicate]}: #{result[:object]}"
        stdout.puts "  Corroboration: #{result[:corroboration_count]} sighting(s)"
        0
      end

      # Server-side corroboration gate + Resolver path — the same logic the
      # memory.promote_observation MCP handler uses. Returns {error:} on refusal
      # or {fact_id:, predicate:, object:, corroboration_count:} on success.
      def promote_observation(store, observation_id, opts)
        obs = store.observations.where(id: observation_id).first
        return {error: "Observation #{observation_id} not found in #{opts[:scope]} database."} unless obs
        return {error: "Observation #{observation_id} already promoted (fact ##{obs[:promoted_fact_id]})."} unless obs[:promoted_at].nil?

        threshold = Domain::Observation::PROMOTION_THRESHOLD
        if obs[:corroboration_count].to_i < threshold
          return {error: "Not yet corroborated: observation #{observation_id} has #{obs[:corroboration_count]} sighting(s), need #{threshold} (anti-hallucination gate)."}
        end

        occurred_at = Time.now.utc.iso8601
        project_path = (opts[:scope] == "global") ? nil : Configuration.new.project_dir
        extraction = Distill::Extraction.new(
          facts: [{subject: opts[:subject], predicate: opts[:predicate], object: opts[:object], strength: "derived"}]
        )
        result = Resolve::Resolver.new(store).apply(
          extraction, content_item_id: obs[:source_content_item_id],
          occurred_at: occurred_at, project_path: project_path, scope: opts[:scope]
        )

        fact_id = result[:fact_ids].compact.first
        return {error: "Promotion failed: the fact for observation #{observation_id} could not be resolved."} unless fact_id

        store.mark_observation_promoted(observation_id, fact_id: fact_id)

        {
          fact_id: fact_id,
          predicate: Resolve::PredicatePolicy.canonicalize(opts[:predicate]),
          object: opts[:object],
          corroboration_count: obs[:corroboration_count]
        }
      end

      # --- consolidate --------------------------------------------------------

      def consolidate(args)
        opts = parse_options(args, {body: nil, kind: "event", priority: Domain::Observation::INFO, scope: "project"}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory observations consolidate <id1,id2,...> --body \"<synthesis>\" [options]"
            parser.on("--body TEXT", "The synthesized observation text") { |v| o[:body] = v }
            parser.on("--kind K", "Kind for the merged observation (default: event)") { |v| o[:kind] = v }
            parser.on("--scope SCOPE", %w[project global], "Database scope (default: project)") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        from_ids = parse_id_list(args.first)
        return failure("Usage: claude-memory observations consolidate <id1,id2,...> --body \"<synthesis>\"") if from_ids.size < 2
        return failure("--body is required") if opts[:body].to_s.strip.empty?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])
        project_path = (opts[:scope] == "global") ? nil : Configuration.new.project_dir

        result = store.consolidate_observations(
          from_ids, body: opts[:body].strip, kind: opts[:kind],
          priority: opts[:priority], scope: opts[:scope], project_path: project_path
        )
        manager.close

        return failure("Need at least 2 active #{opts[:scope]} observations from that set to consolidate.") if result.nil?

        stdout.puts "Consolidated #{result[:merged]} observations -> ##{result[:id]}"
        stdout.puts "  Combined corroboration: #{result[:corroboration_count]} sighting(s)"
        0
      end

      # --- parsing helpers ----------------------------------------------------

      def parse_id(token)
        return nil if token.nil? || !token.match?(/\A\d+\z/)
        token.to_i
      end

      def parse_id_list(token)
        return [] if token.nil?
        token.split(",").map(&:strip).select { |t| t.match?(/\A\d+\z/) }.map(&:to_i).uniq
      end
    end
  end
end
