# frozen_string_literal: true

require "fileutils"

module ClaudeMemory
  module Store
    class StoreManager
      attr_reader :global_store, :project_store, :project_path

      def initialize(global_db_path: nil, project_db_path: nil, project_path: nil, env: ENV)
        @project_path = project_path || env["CLAUDE_PROJECT_DIR"] || Dir.pwd
        @global_db_path = global_db_path || self.class.default_global_db_path(env)
        @project_db_path = project_db_path || self.class.default_project_db_path(@project_path)

        @global_store = nil
        @project_store = nil
      end

      def self.default_global_db_path(env = ENV)
        home = env["HOME"] || File.expand_path("~")
        File.join(home, ".claude", "memory.sqlite3")
      end

      def self.default_project_db_path(project_path = Dir.pwd)
        File.join(project_path, ".claude", "memory.sqlite3")
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

      def promote_fact(fact_id)
        ensure_both!

        fact = @project_store.facts.where(id: fact_id).first
        return nil unless fact

        subject = @project_store.entities.where(id: fact[:subject_entity_id]).first
        return nil unless subject

        global_subject_id = @global_store.find_or_create_entity(
          type: subject[:type],
          name: subject[:canonical_name]
        )

        global_object_id = nil
        if fact[:object_entity_id]
          object = @project_store.entities.where(id: fact[:object_entity_id]).first
          if object
            global_object_id = @global_store.find_or_create_entity(
              type: object[:type],
              name: object[:canonical_name]
            )
          end
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

        copy_provenance(fact_id, global_fact_id)

        global_fact_id
      end

      private

      def copy_provenance(source_fact_id, target_fact_id)
        @project_store.provenance.where(fact_id: source_fact_id).each do |prov|
          @global_store.insert_provenance(
            fact_id: target_fact_id,
            content_item_id: nil,
            quote: prov[:quote],
            attribution_entity_id: nil,
            strength: prov[:strength]
          )
        end
      end
    end
  end
end
