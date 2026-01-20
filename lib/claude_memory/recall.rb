# frozen_string_literal: true

module ClaudeMemory
  class Recall
    def initialize(store, fts: nil)
      @store = store
      @fts = fts || Index::LexicalFTS.new(store)
    end

    def query(query_text, limit: 10)
      content_ids = @fts.search(query_text, limit: limit * 2)
      return [] if content_ids.empty?

      facts_with_provenance = []
      seen_fact_ids = Set.new

      content_ids.each do |content_id|
        provenance_records = find_provenance_by_content(content_id)
        provenance_records.each do |prov|
          next if seen_fact_ids.include?(prov[:fact_id])
          seen_fact_ids.add(prov[:fact_id])

          fact = find_fact(prov[:fact_id])
          next unless fact

          facts_with_provenance << {
            fact: fact,
            receipts: find_receipts(prov[:fact_id])
          }
          break if facts_with_provenance.size >= limit
        end
        break if facts_with_provenance.size >= limit
      end

      facts_with_provenance
    end

    def explain(fact_id)
      fact = find_fact(fact_id)
      return nil unless fact

      {
        fact: fact,
        receipts: find_receipts(fact_id),
        superseded_by: find_superseded_by(fact_id),
        supersedes: find_supersedes(fact_id),
        conflicts: find_conflicts(fact_id)
      }
    end

    def changes(since:, limit: 50)
      rows = @store.execute(
        <<~SQL,
          SELECT id, subject_entity_id, predicate, object_literal, status, created_at
          FROM facts 
          WHERE created_at >= ? 
          ORDER BY created_at DESC 
          LIMIT ?
        SQL
        [since, limit]
      )
      rows.map { |r| {id: r[0], subject_entity_id: r[1], predicate: r[2], object_literal: r[3], status: r[4], created_at: r[5]} }
    end

    private

    def find_provenance_by_content(content_id)
      @store.execute(
        "SELECT id, fact_id, content_item_id, quote, strength FROM provenance WHERE content_item_id = ?",
        [content_id]
      ).map { |r| {id: r[0], fact_id: r[1], content_item_id: r[2], quote: r[3], strength: r[4]} }
    end

    def find_fact(fact_id)
      row = @store.execute(
        <<~SQL,
          SELECT f.id, f.predicate, f.object_literal, f.status, f.confidence, f.valid_from, f.valid_to, f.created_at,
                 e.canonical_name as subject_name
          FROM facts f
          LEFT JOIN entities e ON f.subject_entity_id = e.id
          WHERE f.id = ?
        SQL
        [fact_id]
      ).first
      return nil unless row

      {
        id: row[0],
        predicate: row[1],
        object_literal: row[2],
        status: row[3],
        confidence: row[4],
        valid_from: row[5],
        valid_to: row[6],
        created_at: row[7],
        subject_name: row[8]
      }
    end

    def find_receipts(fact_id)
      @store.execute(
        <<~SQL,
          SELECT p.id, p.quote, p.strength, c.session_id, c.occurred_at
          FROM provenance p
          LEFT JOIN content_items c ON p.content_item_id = c.id
          WHERE p.fact_id = ?
        SQL
        [fact_id]
      ).map { |r| {id: r[0], quote: r[1], strength: r[2], session_id: r[3], occurred_at: r[4]} }
    end

    def find_superseded_by(fact_id)
      @store.execute(
        "SELECT from_fact_id FROM fact_links WHERE to_fact_id = ? AND link_type = 'supersedes'",
        [fact_id]
      ).map(&:first)
    end

    def find_supersedes(fact_id)
      @store.execute(
        "SELECT to_fact_id FROM fact_links WHERE from_fact_id = ? AND link_type = 'supersedes'",
        [fact_id]
      ).map(&:first)
    end

    def find_conflicts(fact_id)
      @store.execute(
        "SELECT id, fact_a_id, fact_b_id, status FROM conflicts WHERE fact_a_id = ? OR fact_b_id = ?",
        [fact_id, fact_id]
      ).map { |r| {id: r[0], fact_a_id: r[1], fact_b_id: r[2], status: r[3]} }
    end
  end
end
