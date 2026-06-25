# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Probes the FTS5 BM25 ranking path (`MATCH ... ORDER BY rank`) — exactly
      # what recall issues. A contentless FTS5 index can corrupt such that plain
      # MATCH, `SELECT count(*)`, and `PRAGMA integrity_check` all pass but
      # `ORDER BY rank` raises "database disk image is malformed", silently
      # breaking recall while every other check reports healthy (issue #7,
      # Finding 2). Recoverable with `claude-memory compact`.
      class FtsRankCheck
        PROBE_TERM = "the" # extremely common; matches any non-trivial English corpus

        def initialize(db_path, label)
          @db_path = db_path
          @label = label
        end

        def call
          return skip_result unless File.exist?(@db_path)

          store = Store::SQLiteStore.new(@db_path)
          begin
            Index::LexicalFTS.new(store).search(PROBE_TERM, limit: 1)
            ok_result
          ensure
            store.close
          end
        rescue Index::LexicalFTS::CorruptRankIndexError
          corrupt_result
        rescue => e
          # Anything unrelated (e.g. no FTS table) is not this check's concern.
          {status: :ok, label: fts_label, message: "#{@label} FTS5 rank probe skipped: #{e.message}", details: {}}
        end

        private

        def fts_label = "#{@label}_fts"

        def ok_result
          {status: :ok, label: fts_label, message: "#{@label} FTS5 rank path: healthy", details: {}}
        end

        def corrupt_result
          {
            status: :error,
            label: fts_label,
            message: "#{@label} FTS5 rank index is corrupt — recall is broken (integrity_check misses this). Run 'claude-memory compact' to rebuild.",
            details: {}
          }
        end

        def skip_result
          {status: :ok, label: fts_label, message: "#{@label} FTS5: no database", details: {}}
        end
      end
    end
  end
end
