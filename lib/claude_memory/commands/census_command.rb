# frozen_string_literal: true

require "json"
require "digest"

module ClaudeMemory
  module Commands
    # Aggregates predicate/entity/schema usage across many ClaudeMemory databases
    # into a privacy-safe JSON report. Used for informed vocabulary curation
    # across machines without exposing content, names, or paths.
    #
    # What's emitted: schema versions, fact counts by predicate × status,
    # entity type counts, novel predicates (outside the curated vocabulary),
    # and synonym candidates (novel predicates overlapping known ones).
    #
    # What's *never* emitted: object_literal, entity names, project paths,
    # provenance quotes, raw session IDs.
    class CensusCommand < BaseCommand
      DB_FILENAME = "memory.sqlite3"
      TOP_PREDICATES_PER_DB = 5
      SYNONYM_OVERLAP_THRESHOLD = 0.4
      DEFAULT_ROOT = "~/src"

      def call(args)
        opts = parse_options(args, {root: DEFAULT_ROOT, output: nil, pretty: false, include_global: true}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory census [options]"
            parser.on("--root DIR", "Directory to scan (default: #{DEFAULT_ROOT})") { |v| o[:root] = v }
            parser.on("--output FILE", "Write JSON to file instead of stdout") { |v| o[:output] = v }
            parser.on("--pretty", "Pretty-print JSON output") { o[:pretty] = true }
            parser.on("--no-global", "Skip the global database (~/.claude/memory.sqlite3)") { o[:include_global] = false }
          end
        end
        return 1 if opts.nil?

        root = File.expand_path(opts[:root])
        paths = discover_databases(root)
        paths << global_db_path if opts[:include_global] && File.exist?(global_db_path) && !paths.include?(global_db_path)

        if paths.empty?
          stderr.puts "No ClaudeMemory databases found under #{root}"
          return 0
        end

        report = build_report(paths)
        json = opts[:pretty] ? JSON.pretty_generate(report) : JSON.generate(report)

        if opts[:output]
          File.write(opts[:output], json)
          stderr.puts "Census: scanned #{paths.size} database(s); wrote #{opts[:output]}"
        else
          stdout.puts json
        end

        0
      end

      private

      def global_db_path
        ClaudeMemory::Configuration.new.global_db_path
      end

      def discover_databases(root)
        return [] unless Dir.exist?(root)
        Dir.glob(File.join(root, "**", ".claude", DB_FILENAME)).sort
      end

      def build_report(paths)
        known = ClaudeMemory::Resolve::PredicatePolicy.known_predicates.to_set

        report = {
          version: ClaudeMemory::VERSION,
          generated_at: Time.now.utc.iso8601,
          database_count: paths.size,
          schema_versions: Hash.new(0),
          totals: {facts: Hash.new(0), entities: 0, content_items: 0},
          predicates: {},
          entity_types: Hash.new(0),
          novel_predicates: [],
          synonym_candidates: [],
          databases: []
        }

        predicates = Hash.new { |h, k| h[k] = {total: 0, by_status: Hash.new(0), db_count: 0} }

        paths.each do |path|
          summary = scan_database(path)
          next unless summary

          report[:schema_versions][summary[:schema_version].to_s] += 1 if summary[:schema_version]
          report[:totals][:entities] += summary[:entity_count]
          report[:totals][:content_items] += summary[:content_count]

          summary[:facts_by_status].each { |status, count| report[:totals][:facts][status] += count }

          summary[:entity_types].each { |type, count| report[:entity_types][type.to_s] += count }

          summary[:predicates].each do |predicate, statuses|
            entry = predicates[predicate]
            entry[:db_count] += 1
            statuses.each do |status, count|
              entry[:total] += count
              entry[:by_status][status] += count
            end
          end

          report[:databases] << anonymize_db(path, summary)
        end

        report[:predicates] = predicates.each_with_object({}) do |(predicate, entry), acc|
          acc[predicate] = {
            total: entry[:total],
            by_status: entry[:by_status],
            db_count: entry[:db_count],
            known: known.include?(predicate)
          }
        end

        report[:novel_predicates] = predicates.keys.reject { |p| known.include?(p) }.sort
        report[:synonym_candidates] = synonym_candidates(report[:novel_predicates], known)

        report
      end

      def scan_database(path)
        db = Sequel.connect("extralite://#{path}")

        schema_version = begin
          db[:meta].where(key: "schema_version").get(:value)&.to_i
        rescue Sequel::DatabaseError
          nil
        end

        facts_by_status = db[:facts].group_and_count(:status).all.each_with_object(Hash.new(0)) do |row, acc|
          acc[row[:status].to_s] += row[:count].to_i
        end

        predicates = db[:facts].select(:predicate, :status).group_and_count(:predicate, :status).all
          .each_with_object(Hash.new { |h, k| h[k] = Hash.new(0) }) do |row, acc|
          acc[row[:predicate].to_s][row[:status].to_s] += row[:count].to_i
        end

        entity_types = db[:entities].group_and_count(:type).all.each_with_object(Hash.new(0)) do |row, acc|
          acc[row[:type].to_s] += row[:count].to_i
        end

        entity_count = db[:entities].count
        content_count = db[:content_items].count

        {
          schema_version: schema_version,
          facts_by_status: facts_by_status,
          predicates: predicates,
          entity_types: entity_types,
          entity_count: entity_count,
          content_count: content_count
        }
      rescue Sequel::DatabaseError, Extralite::Error => e
        stderr.puts "Skipping #{path}: #{e.message}"
        nil
      ensure
        db&.disconnect
      end

      def anonymize_db(path, summary)
        top = summary[:predicates]
          .map { |predicate, statuses| [predicate, statuses.values.sum] }
          .sort_by { |(_, count)| -count }
          .first(TOP_PREDICATES_PER_DB)
          .to_h

        {
          id: Digest::SHA256.hexdigest(path)[0, 12],
          schema_version: summary[:schema_version],
          facts: summary[:facts_by_status],
          entities: summary[:entity_count],
          content_items: summary[:content_count],
          top_predicates: top
        }
      end

      def synonym_candidates(novels, known)
        novels.each_with_object([]) do |novel, acc|
          novel_tokens = tokenize(novel)
          next if novel_tokens.empty?

          best = known.map do |canonical|
            {canonical: canonical, overlap: jaccard(novel_tokens, tokenize(canonical))}
          end.max_by { |candidate| candidate[:overlap] }

          next unless best && best[:overlap] >= SYNONYM_OVERLAP_THRESHOLD

          acc << {novel: novel, closest_known: best[:canonical], overlap: best[:overlap].round(2)}
        end
      end

      def tokenize(predicate)
        predicate.to_s.downcase.split(/[_\s-]+/).reject(&:empty?).to_set
      end

      def jaccard(a, b)
        return 0.0 if a.empty? || b.empty?
        intersection = (a & b).size
        union = (a | b).size
        union.zero? ? 0.0 : intersection.to_f / union
      end
    end
  end
end
