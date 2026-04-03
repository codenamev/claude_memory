# frozen_string_literal: true

require "fileutils"

module ClaudeMemory
  module Store
    class StoreManager
      attr_reader :global_store, :project_store, :project_path

      def initialize(global_db_path: nil, project_db_path: nil, project_path: nil, env: ENV)
        config = Configuration.new(env)
        @project_path = project_path || config.project_dir
        @global_db_path = global_db_path || config.global_db_path
        @project_db_path = project_db_path || config.project_db_path(@project_path)

        @global_store = nil
        @project_store = nil
      end

      def self.default_global_db_path(env = ENV)
        Configuration.new(env).global_db_path
      end

      def self.default_project_db_path(project_path = Dir.pwd)
        Configuration.new.project_db_path(project_path)
      end

      def ensure_global!
        return @global_store if @global_store

        FileUtils.mkdir_p(File.dirname(@global_db_path))
        @global_store = SQLiteStore.new(@global_db_path)
      end

      def ensure_project!
        return @project_store if @project_store

        FileUtils.mkdir_p(File.dirname(@project_db_path))
        @project_store = SQLiteStore.new(@project_db_path)
      end

      def ensure_both!
        ensure_global!
        ensure_project!
      end

      attr_reader :global_db_path

      attr_reader :project_db_path

      def global_exists?
        File.exist?(@global_db_path)
      end

      def project_exists?
        File.exist?(@project_db_path)
      end

      def close
        @global_store&.close
        @project_store&.close
        @global_store = nil
        @project_store = nil
      end

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

      # Yields each store with its source label ("project"/"global").
      # Scope "all" yields both, "project"/"global" yields one.
      def each_store(scope: "all")
        case scope
        when "all"
          if project_exists?
            ensure_project!
            yield @project_store, "project"
          end
          if global_exists?
            ensure_global!
            yield @global_store, "global"
          end
        when "project"
          ensure_project!
          yield @project_store, "project"
        when "global"
          ensure_global!
          yield @global_store, "global"
        end
      end

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
            project_path: nil,
            category: fact[:category] || "general"
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
