# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Promotes a project fact to global memory
    class PromoteCommand < BaseCommand
      def call(args)
        fact_id = args.first&.to_i
        unless fact_id && fact_id > 0
          stderr.puts "Usage: claude-memory promote <fact_id>"
          stderr.puts "\nPromotes a project fact to the global database."
          return 1
        end

        manager = ClaudeMemory::Store::StoreManager.new
        global_fact_id = manager.promote_fact(fact_id)

        if global_fact_id
          stdout.puts "Promoted fact ##{fact_id} to global database as fact ##{global_fact_id}"
          manager.close
          0
        else
          stderr.puts "Fact ##{fact_id} not found in project database."
          manager.close
          1
        end
      end
    end
  end
end
