# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Checks sqlite-vec extension availability and index coverage
      class VecCheck
        def call
          vec_available = check_vec_availability
          coverage = check_vec_coverage

          warnings = []
          unless vec_available
            warnings << "sqlite-vec extension not available (vector search uses slower JSON fallback)"
          end

          if vec_available && coverage && coverage[:coverage_pct] < 100 && coverage[:with_embedding] > 0
            warnings << "Vec index coverage: #{coverage[:coverage_pct]}% (#{coverage[:vec_indexed]}/#{coverage[:with_embedding]} facts). Run 'claude-memory index --vec' to backfill."
          end

          {
            status: warnings.any? ? :warning : :ok,
            label: "sqlite-vec",
            message: vec_available ? "sqlite-vec available" : "sqlite-vec not available",
            details: {
              available: vec_available,
              coverage: coverage
            },
            warnings: warnings
          }
        end

        private

        def check_vec_availability
          require "sqlite_vec"
          true
        rescue LoadError
          false
        end

        def check_vec_coverage
          config = Configuration.new
          totals = {vec_indexed: 0, with_embedding: 0, coverage_pct: 0}

          [config.global_db_path, config.project_db_path].each do |db_path|
            next unless File.exist?(db_path)

            store = nil
            begin
              store = Store::SQLiteStore.new(db_path)
              stats = store.vector_index.coverage_stats
              totals[:with_embedding] += stats[:with_embedding]
              totals[:vec_indexed] += stats[:vec_indexed]
            rescue => _e
              next
            ensure
              store&.close
            end
          end

          totals[:coverage_pct] = if totals[:with_embedding] > 0
            (totals[:vec_indexed] * 100.0 / totals[:with_embedding]).round(1)
          else
            0
          end

          totals
        end
      end
    end
  end
end
