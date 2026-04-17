# frozen_string_literal: true

require "fileutils"

module ClaudeMemory
  module Store
    # Dual-database connection manager for global and project stores.
    # Lazily opens SQLiteStore connections to the global database
    # (~/.claude/memory.sqlite3) and the project database
    # (.claude/memory.sqlite3 under the project root). Commands query
    # both databases by default, with project facts taking precedence.
    class StoreManager
      # @return [SQLiteStore, nil] global store (nil until {#ensure_global!} is called)
      attr_reader :global_store

      # @return [SQLiteStore, nil] project store (nil until {#ensure_project!} is called)
      attr_reader :project_store

      # @return [String] project directory path
      attr_reader :project_path

      # @param global_db_path [String, nil] override path to the global database
      # @param project_db_path [String, nil] override path to the project database
      # @param project_path [String, nil] project directory (defaults to Configuration)
      # @param env [Hash] environment variable hash (default: ENV)
      def initialize(global_db_path: nil, project_db_path: nil, project_path: nil, env: ENV)
        config = Configuration.new(env)
        @project_path = project_path || config.project_dir
        @global_db_path = global_db_path || config.global_db_path
        @project_db_path = project_db_path || config.project_db_path(@project_path)

        @global_store = nil
        @project_store = nil
      end

      # Default global database path from Configuration.
      # @param env [Hash] environment variable hash
      # @return [String]
      def self.default_global_db_path(env = ENV)
        Configuration.new(env).global_db_path
      end

      # Default project database path for a given project directory.
      # @param project_path [String] project directory (default: current working directory)
      # @return [String]
      def self.default_project_db_path(project_path = Dir.pwd)
        Configuration.new.project_db_path(project_path)
      end

      # Open the global store, creating the directory and database if needed.
      # No-op if already open.
      # @return [SQLiteStore] the global store
      def ensure_global!
        return @global_store if @global_store

        FileUtils.mkdir_p(File.dirname(@global_db_path))
        @global_store = SQLiteStore.new(@global_db_path)
      end

      # Open the project store, creating the directory and database if needed.
      # No-op if already open.
      # @return [SQLiteStore] the project store
      def ensure_project!
        return @project_store if @project_store

        FileUtils.mkdir_p(File.dirname(@project_db_path))
        @project_store = SQLiteStore.new(@project_db_path)
      end

      # Open both global and project stores.
      # @return [void]
      def ensure_both!
        ensure_global!
        ensure_project!
      end

      # @return [String] filesystem path to the global database
      attr_reader :global_db_path

      # @return [String] filesystem path to the project database
      attr_reader :project_db_path

      # Check whether the global database file exists on disk.
      # @return [Boolean]
      def global_exists?
        File.exist?(@global_db_path)
      end

      # Check whether the project database file exists on disk.
      # @return [Boolean]
      def project_exists?
        File.exist?(@project_db_path)
      end

      # Close both database connections and reset store references.
      # @return [void]
      def close
        @global_store&.close
        @project_store&.close
        @global_store = nil
        @project_store = nil
      end

      # Return the appropriate store for a given scope string.
      # @param scope [String] "global" or "project"
      # @return [SQLiteStore]
      # @raise [ArgumentError] if scope is not "global" or "project"
      def store_for_scope(scope)
        case scope
        when "global"
          ensure_global!
          @global_store
        when "project"
          ensure_project!
          @project_store
        else
          raise ArgumentError, "Invalid scope: #{scope}. Use 'global' or 'project'"
        end
      end

      # Return the store for an explicit scope only if its database file
      # already exists on disk. Never creates a new DB. Useful for
      # read-only surfaces that want to avoid accidental initialization.
      # @param scope [String] "global" or "project"
      # @return [SQLiteStore, nil]
      def store_if_exists(scope)
        case scope
        when "project"
          return nil unless project_exists?
          ensure_project!
        when "global"
          return nil unless global_exists?
          ensure_global!
        end
      end

      # Return whichever store is available, preferring the requested scope.
      # Falls back to the other scope if the preferred DB doesn't exist on
      # disk yet. Returns nil only when both DBs are missing. Intended for
      # "best-effort" surfaces like activity logging and default dashboard
      # reads where the caller just needs some store to talk to.
      # @param prefer [Symbol] :project (default) or :global
      # @return [SQLiteStore, nil]
      def default_store(prefer: :project)
        primary = (prefer == :global) ? "global" : "project"
        fallback = (prefer == :global) ? "project" : "global"
        store_if_exists(primary) || store_if_exists(fallback)
      end

      # Copy a project-scoped fact (with its entities and provenance) into the
      # global store, making it available across all projects. Runs the global
      # writes in a single transaction for atomicity.
      #
      # @param fact_id [Integer] project fact row id to promote
      # @return [Integer, nil] the new global fact id, or nil if the fact/subject
      #   was not found in the project store
      def promote_fact(fact_id)
        ensure_both!

        fact = @project_store.facts.where(id: fact_id).first
        return nil unless fact

        subject = @project_store.entities.where(id: fact[:subject_entity_id]).first
        return nil unless subject

        # Read all project data before entering global transaction
        object = fact[:object_entity_id] ? @project_store.entities.where(id: fact[:object_entity_id]).first : nil
        provenance_records = @project_store.provenance.where(fact_id: fact_id).all

        # Wrap all global database operations in a transaction for atomicity
        @global_store.db.transaction do
          global_subject_id = @global_store.find_or_create_entity(
            type: subject[:type],
            name: subject[:canonical_name]
          )

          global_object_id = nil
          if object
            global_object_id = @global_store.find_or_create_entity(
              type: object[:type],
              name: object[:canonical_name]
            )
          end

          global_fact_id = @global_store.insert_fact(
            subject_entity_id: global_subject_id,
            predicate: fact[:predicate],
            object_entity_id: global_object_id,
            object_literal: fact[:object_literal],
            datatype: fact[:datatype],
            polarity: fact[:polarity],
            valid_from: fact[:valid_from],
            status: fact[:status],
            confidence: fact[:confidence],
            created_from: "promoted:#{@project_path}:#{fact_id}",
            scope: "global",
            project_path: nil
          )

          provenance_records.each do |prov|
            @global_store.insert_provenance(
              fact_id: global_fact_id,
              content_item_id: nil,
              quote: prov[:quote],
              attribution_entity_id: nil,
              strength: prov[:strength]
            )
          end

          global_fact_id
        end
      end
    end
  end
end
