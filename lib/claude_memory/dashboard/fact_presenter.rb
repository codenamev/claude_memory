# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Shapes a facts-table row into the hashes the dashboard API emits.
    # Callers opt in to the shape they need:
    #
    # - {#summary}         — full fact with confidence, scope, created_at, created_ago
    # - {#preview}         — predicate + truncated object for list rows
    # - {#with_provenance} — summary + provenance chain (quote, session_id, occurred_at)
    # - {#list_summary}    — batches entity lookups across many rows to avoid N+1
    #
    # All methods resolve the subject/object entities from the store passed at
    # construction time; callers pass in raw facts-table rows (hashes) directly.
    class FactPresenter
      OBJECT_PREVIEW_CHARS = 120

      def initialize(store)
        @store = store
      end

      # @param row [Hash, nil] a facts-table row
      # @return [Hash, nil] nil when row is nil
      def summary(row)
        return nil unless row
        serialize(row, load_entities([row[:subject_entity_id], row[:object_entity_id]]))
      end

      # @param row [Hash, nil]
      # @return [Hash, nil] object text truncated to {OBJECT_PREVIEW_CHARS}
      def preview(row)
        return nil unless row
        entities = load_entities([row[:subject_entity_id], row[:object_entity_id]])
        subject = entities[row[:subject_entity_id]]
        object_entity = entities[row[:object_entity_id]]
        object_text = row[:object_literal] || object_entity&.dig(:canonical_name) || "unknown"
        truncated = object_text.to_s.length > OBJECT_PREVIEW_CHARS

        {
          id: row[:id],
          docid: row[:docid],
          subject: subject&.dig(:canonical_name) || "unknown",
          predicate: row[:predicate],
          object: truncated ? "#{object_text[0, OBJECT_PREVIEW_CHARS]}…" : object_text,
          scope: row[:scope],
          status: row[:status]
        }
      end

      # @param row [Hash, nil]
      # @return [Hash, nil] summary plus :provenance array with session/date context
      def with_provenance(row)
        return nil unless row
        summary(row).merge(provenance: load_provenance(row[:id]))
      end

      # @param rows [Array<Hash>] facts-table rows
      # @return [Array<Hash>] summaries with batched entity resolution
      def list_summary(rows)
        ids = rows.flat_map { |r| [r[:subject_entity_id], r[:object_entity_id]] }.compact.uniq
        entities = ids.empty? ? {} : @store.entities.where(id: ids).as_hash(:id)
        rows.map { |r| serialize(r, entities) }
      end

      private

      def load_entities(ids)
        valid = ids.compact.uniq
        return {} if valid.empty?
        @store.entities.where(id: valid).as_hash(:id)
      end

      def load_provenance(fact_id)
        prov_rows = @store.provenance.where(fact_id: fact_id).all
        content_ids = prov_rows.map { |p| p[:content_item_id] }.compact.uniq
        content_items = content_ids.empty? ? {} : @store.content_items.where(id: content_ids).as_hash(:id)

        prov_rows.map { |p|
          ci = p[:content_item_id] ? content_items[p[:content_item_id]] : nil
          {
            quote: p[:quote],
            strength: p[:strength],
            content_item_id: p[:content_item_id],
            session_id: ci&.dig(:session_id),
            occurred_at: ci&.dig(:occurred_at)
          }
        }
      end

      def serialize(row, entities)
        subject = entities[row[:subject_entity_id]]
        object_entity = entities[row[:object_entity_id]]
        {
          id: row[:id],
          docid: row[:docid],
          subject: subject&.dig(:canonical_name) || "unknown",
          predicate: row[:predicate],
          object: row[:object_literal] || object_entity&.dig(:canonical_name) || "unknown",
          status: row[:status],
          confidence: row[:confidence],
          scope: row[:scope],
          created_at: row[:created_at],
          created_ago: Core::RelativeTime.format(row[:created_at]),
          valid_from: row[:valid_from]
        }
      end
    end
  end
end
