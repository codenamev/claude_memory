# frozen_string_literal: true

module ClaudeMemory
  module Store
    # Schema migration and version management for SQLiteStore.
    # Handles Sequel migrations, legacy version syncing, and initial setup.
    module SchemaManager
      SCHEMA_VERSION = 17

      private

      def ensure_schema!
        migrations_path = File.expand_path("../../../db/migrations", __dir__)

        # Handle backward compatibility: databases created with old migration system
        sync_legacy_schema_version!

        # Skip migration if the database is already ahead of this gem's version.
        # This happens when a newer gem version migrated the DB and an older
        # installed gem (e.g. via hooks) tries to open it.
        current = current_schema_version
        return if current && current > SCHEMA_VERSION

        # Run Sequel migrations to bring database to target version
        Sequel::Migrator.run(@db, migrations_path, target: SCHEMA_VERSION)

        # Set created_at timestamp on first initialization
        set_meta("created_at", Time.now.utc.iso8601) unless get_meta("created_at")

        # Sync legacy schema_version meta key with Sequel's schema_info
        # This maintains backwards compatibility with code that reads schema_version
        sequel_version = @db[:schema_info].get(:version) if @db.table_exists?(:schema_info)
        set_meta("schema_version", sequel_version.to_s) if sequel_version
      end

      # Sync legacy schema_version from meta table to Sequel's schema_info
      # Handles two cases:
      # 1. No schema_info table exists (old system, pre-Sequel migrations)
      # 2. schema_info exists but is out of sync with meta.schema_version
      def sync_legacy_schema_version!
        return unless @db.table_exists?(:meta)

        meta_version = get_meta("schema_version")&.to_i
        return unless meta_version && meta_version >= 2

        # Verify database actually has v2+ schema (defensive check)
        columns = @db.schema(:content_items).map(&:first) if @db.table_exists?(:content_items)
        return unless columns&.include?(:project_path)

        # Create or update schema_info to match meta.schema_version
        @db.create_table?(:schema_info) do
          Integer :version, null: false, default: 0
        end

        sequel_version = @db[:schema_info].get(:version)
        if sequel_version.nil? || sequel_version < meta_version
          @db[:schema_info].delete
          @db[:schema_info].insert(version: meta_version)
        end
      end

      def current_schema_version
        return nil unless @db.table_exists?(:schema_info)
        @db[:schema_info].get(:version)
      end
    end
  end
end
