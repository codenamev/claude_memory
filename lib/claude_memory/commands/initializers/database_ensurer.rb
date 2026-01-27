# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Initializers
      # Ensures databases are created and ready
      class DatabaseEnsurer
        def initialize(stdout)
          @stdout = stdout
        end

        def ensure_project_databases
          manager = ClaudeMemory::Store::StoreManager.new
          manager.ensure_global!
          @stdout.puts "✓ Global database: #{manager.global_db_path}"
          manager.ensure_project!
          @stdout.puts "✓ Project database: #{manager.project_db_path}"
          manager.close
        end

        def ensure_global_database
          manager = ClaudeMemory::Store::StoreManager.new
          manager.ensure_global!
          @stdout.puts "✓ Created global database: #{manager.global_db_path}"
          manager.close
        end
      end
    end
  end
end
