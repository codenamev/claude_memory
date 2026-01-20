# frozen_string_literal: true

require "sqlite3"
require "json"

module ClaudeMemory
  module Store
    class SQLiteStore
      SCHEMA_VERSION = 1

      attr_reader :db

      def initialize(db_path)
        @db_path = db_path
        @db = SQLite3::Database.new(db_path)
        @db.results_as_hash = false
        ensure_schema!
      end

      def close
        @db.close
      end

      def execute(sql, params = [])
        @db.execute(sql, params)
      end

      def schema_version
        result = @db.get_first_value("SELECT value FROM meta WHERE key = ?", ["schema_version"])
        result&.to_i
      end

      private

      def ensure_schema!
        create_tables!
        set_meta("schema_version", SCHEMA_VERSION.to_s)
        set_meta("created_at", Time.now.utc.iso8601) unless get_meta("created_at")
      end

      def create_tables!
        @db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT
          );

          CREATE TABLE IF NOT EXISTS content_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            session_id TEXT,
            transcript_path TEXT,
            occurred_at TEXT,
            ingested_at TEXT NOT NULL,
            text_hash TEXT NOT NULL,
            byte_len INTEGER NOT NULL,
            raw_text TEXT,
            metadata_json TEXT
          );

          CREATE TABLE IF NOT EXISTS delta_cursors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            transcript_path TEXT NOT NULL,
            last_byte_offset INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            UNIQUE(session_id, transcript_path)
          );

          CREATE TABLE IF NOT EXISTS entities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            canonical_name TEXT NOT NULL,
            slug TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL
          );

          CREATE TABLE IF NOT EXISTS entity_aliases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_id INTEGER NOT NULL REFERENCES entities(id),
            source TEXT,
            alias TEXT NOT NULL,
            confidence REAL DEFAULT 1.0
          );

          CREATE TABLE IF NOT EXISTS facts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject_entity_id INTEGER REFERENCES entities(id),
            predicate TEXT NOT NULL,
            object_entity_id INTEGER REFERENCES entities(id),
            object_literal TEXT,
            datatype TEXT,
            polarity TEXT DEFAULT 'positive',
            valid_from TEXT,
            valid_to TEXT,
            status TEXT DEFAULT 'active',
            confidence REAL DEFAULT 1.0,
            created_from TEXT,
            created_at TEXT NOT NULL
          );

          CREATE TABLE IF NOT EXISTS provenance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fact_id INTEGER NOT NULL REFERENCES facts(id),
            content_item_id INTEGER REFERENCES content_items(id),
            quote TEXT,
            attribution_entity_id INTEGER REFERENCES entities(id),
            strength TEXT DEFAULT 'stated'
          );

          CREATE TABLE IF NOT EXISTS fact_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_fact_id INTEGER NOT NULL REFERENCES facts(id),
            to_fact_id INTEGER NOT NULL REFERENCES facts(id),
            link_type TEXT NOT NULL
          );

          CREATE TABLE IF NOT EXISTS conflicts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fact_a_id INTEGER NOT NULL REFERENCES facts(id),
            fact_b_id INTEGER NOT NULL REFERENCES facts(id),
            status TEXT DEFAULT 'open',
            detected_at TEXT NOT NULL,
            notes TEXT
          );

          CREATE INDEX IF NOT EXISTS idx_facts_predicate ON facts(predicate);
          CREATE INDEX IF NOT EXISTS idx_facts_subject ON facts(subject_entity_id);
          CREATE INDEX IF NOT EXISTS idx_facts_status ON facts(status);
          CREATE INDEX IF NOT EXISTS idx_provenance_fact ON provenance(fact_id);
          CREATE INDEX IF NOT EXISTS idx_entity_aliases_entity ON entity_aliases(entity_id);
          CREATE INDEX IF NOT EXISTS idx_content_items_session ON content_items(session_id);
        SQL
      end

      def set_meta(key, value)
        @db.execute(
          "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
          [key, value]
        )
      end

      def get_meta(key)
        @db.get_first_value("SELECT value FROM meta WHERE key = ?", [key])
      end

      public

      def upsert_content_item(source:, text_hash:, byte_len:, session_id: nil, transcript_path: nil,
        occurred_at: nil, raw_text: nil, metadata: nil)
        existing = @db.get_first_value(
          "SELECT id FROM content_items WHERE text_hash = ? AND session_id = ?",
          [text_hash, session_id]
        )
        return existing if existing

        now = Time.now.utc.iso8601
        @db.execute(
          <<~SQL,
            INSERT INTO content_items 
              (source, session_id, transcript_path, occurred_at, ingested_at, text_hash, byte_len, raw_text, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [source, session_id, transcript_path, occurred_at || now, now, text_hash, byte_len, raw_text, metadata&.to_json]
        )
        @db.last_insert_row_id
      end

      def get_delta_cursor(session_id, transcript_path)
        @db.get_first_value(
          "SELECT last_byte_offset FROM delta_cursors WHERE session_id = ? AND transcript_path = ?",
          [session_id, transcript_path]
        )
      end

      def update_delta_cursor(session_id, transcript_path, offset)
        now = Time.now.utc.iso8601
        @db.execute(
          <<~SQL,
            INSERT INTO delta_cursors (session_id, transcript_path, last_byte_offset, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(session_id, transcript_path) DO UPDATE SET last_byte_offset = ?, updated_at = ?
          SQL
          [session_id, transcript_path, offset, now, offset, now]
        )
      end

      def find_or_create_entity(type:, name:)
        slug = slugify(type, name)
        existing = @db.get_first_value("SELECT id FROM entities WHERE slug = ?", [slug])
        return existing if existing

        now = Time.now.utc.iso8601
        @db.execute(
          "INSERT INTO entities (type, canonical_name, slug, created_at) VALUES (?, ?, ?, ?)",
          [type, name, slug, now]
        )
        @db.last_insert_row_id
      end

      def insert_fact(subject_entity_id:, predicate:, object_entity_id: nil, object_literal: nil,
        datatype: nil, polarity: "positive", valid_from: nil, status: "active",
        confidence: 1.0, created_from: nil)
        now = Time.now.utc.iso8601
        @db.execute(
          <<~SQL,
            INSERT INTO facts 
              (subject_entity_id, predicate, object_entity_id, object_literal, datatype, polarity, valid_from, status, confidence, created_from, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [subject_entity_id, predicate, object_entity_id, object_literal, datatype, polarity, valid_from || now, status, confidence, created_from, now]
        )
        @db.last_insert_row_id
      end

      def update_fact(fact_id, status: nil, valid_to: nil)
        updates = []
        params = []

        if status
          updates << "status = ?"
          params << status
        end

        if valid_to
          updates << "valid_to = ?"
          params << valid_to
        end

        return if updates.empty?

        params << fact_id
        @db.execute("UPDATE facts SET #{updates.join(", ")} WHERE id = ?", params)
      end

      def facts_for_slot(subject_entity_id, predicate, status: "active")
        rows = @db.execute(
          <<~SQL,
            SELECT id, subject_entity_id, predicate, object_entity_id, object_literal, datatype, 
                   polarity, valid_from, valid_to, status, confidence, created_from, created_at
            FROM facts 
            WHERE subject_entity_id = ? AND predicate = ? AND status = ?
          SQL
          [subject_entity_id, predicate, status]
        )
        rows.map { |row| row_to_fact_hash(row) }
      end

      def insert_provenance(fact_id:, content_item_id: nil, quote: nil, attribution_entity_id: nil, strength: "stated")
        @db.execute(
          "INSERT INTO provenance (fact_id, content_item_id, quote, attribution_entity_id, strength) VALUES (?, ?, ?, ?, ?)",
          [fact_id, content_item_id, quote, attribution_entity_id, strength]
        )
        @db.last_insert_row_id
      end

      def provenance_for_fact(fact_id)
        rows = @db.execute(
          "SELECT id, fact_id, content_item_id, quote, attribution_entity_id, strength FROM provenance WHERE fact_id = ?",
          [fact_id]
        )
        rows.map do |row|
          {id: row[0], fact_id: row[1], content_item_id: row[2], quote: row[3], attribution_entity_id: row[4], strength: row[5]}
        end
      end

      def insert_conflict(fact_a_id:, fact_b_id:, status: "open", notes: nil)
        now = Time.now.utc.iso8601
        @db.execute(
          "INSERT INTO conflicts (fact_a_id, fact_b_id, status, detected_at, notes) VALUES (?, ?, ?, ?, ?)",
          [fact_a_id, fact_b_id, status, now, notes]
        )
        @db.last_insert_row_id
      end

      def open_conflicts
        rows = @db.execute("SELECT id, fact_a_id, fact_b_id, status, detected_at, notes FROM conflicts WHERE status = 'open'")
        rows.map do |row|
          {id: row[0], fact_a_id: row[1], fact_b_id: row[2], status: row[3], detected_at: row[4], notes: row[5]}
        end
      end

      def insert_fact_link(from_fact_id:, to_fact_id:, link_type:)
        @db.execute(
          "INSERT INTO fact_links (from_fact_id, to_fact_id, link_type) VALUES (?, ?, ?)",
          [from_fact_id, to_fact_id, link_type]
        )
        @db.last_insert_row_id
      end

      private

      def slugify(type, name)
        "#{type}:#{name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")}"
      end

      def row_to_fact_hash(row)
        {
          id: row[0],
          subject_entity_id: row[1],
          predicate: row[2],
          object_entity_id: row[3],
          object_literal: row[4],
          datatype: row[5],
          polarity: row[6],
          valid_from: row[7],
          valid_to: row[8],
          status: row[9],
          confidence: row[10],
          created_from: row[11],
          created_at: row[12]
        }
      end
    end
  end
end
