# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"
require_relative "claude_cli_runner"
require_relative "simple_acceptance_criteria"

# Week 2: Extracted common patterns from Week 1 spike
# Only extracted after seeing clear repetition across 3 evals

module EvalHelpers
  # Common RSpec setup for all eval scenarios
  module SharedSetup
    def self.included(base)
      base.class_eval do
        let(:tmpdir) { Dir.mktmpdir("#{eval_name}_#{Process.pid}") }
        let(:db_path) { File.join(tmpdir, ".claude/memory.sqlite3") }

        before do
          FileUtils.mkdir_p(File.dirname(db_path))
        end

        after do
          FileUtils.rm_rf(tmpdir)
        end

        # Subclasses must define this to identify the eval
        def eval_name
          self.class.description.downcase.gsub(/\s+/, "_")
        end

        # CLI runner helpers
        def baseline_runner
          @baseline_runner ||= CliRunnerFactory.baseline_runner
        end

        def memory_runner
          # Run Claude in tmpdir where fixture database is created
          # Copy MCP config so Claude loads the memory server
          setup_mcp_config_in_tmpdir
          @memory_runner ||= CliRunnerFactory.memory_enabled_runner(tmpdir)
        end

        def setup_mcp_config_in_tmpdir
          # Copy actual MCP config from project root to keep it in sync
          source_config = File.join(project_root, ".mcp.json")
          dest_config = File.join(tmpdir, ".mcp.json")
          FileUtils.cp(source_config, dest_config) if File.exist?(source_config)
        end

        def project_root
          File.expand_path("../../..", __dir__)
        end

        def eval_mode
          ENV["EVAL_MODE"] || "stub"
        end
      end
    end
  end

  # Helper for building memory fixtures with facts, content, and provenance
  class MemoryFixtureBuilder
    attr_reader :store, :fts

    def initialize(db_path)
      @db_path = db_path
      @store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      @fts = ClaudeMemory::Index::LexicalFTS.new(@store)
      @entity_id = nil
    end

    # Get or create the default test entity
    def entity_id
      @entity_id ||= store.find_or_create_entity(type: "repo", name: "test-project")
    end

    # Add a single fact with content and provenance
    def add_fact(predicate:, object:, text:, fts_keywords: nil, scope: "project")
      # Create content item
      content_id = store.upsert_content_item(
        source: "test",
        session_id: "test-session",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize,
        raw_text: text
      )

      # Create fact
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: predicate,
        object_literal: object,
        scope: scope
      )

      # Link fact to content (provenance)
      store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: object,
        strength: "stated"
      )

      # Index for FTS
      fts_text = fts_keywords ? "#{text} #{fts_keywords}" : text
      fts.index_content_item(content_id, fts_text)

      fact_id
    end

    # Add multiple facts at once
    def add_facts(facts_data)
      facts_data.map do |data|
        add_fact(
          predicate: data[:predicate],
          object: data[:object],
          text: data[:text],
          fts_keywords: data[:fts_keywords],
          scope: data.fetch(:scope, "project")
        )
      end
    end

    # Close the store when done
    def close
      store.close
    end
  end

  # Helper for creating stubbed Claude responses
  module ResponseStubs
    def stub_success_response(text, session_id: nil)
      {
        success: true,
        result: text,
        session_id: session_id || "stub-session-#{rand(1000)}"
      }
    end

    def stub_failure_response(error)
      {
        success: false,
        error: error
      }
    end
  end

  # Helper for calculating behavioral scores
  module ScoringHelpers
    # Check if response includes all required terms
    def includes_all?(response, *terms)
      terms.all? { |term| response.downcase.include?(term.downcase) }
    end

    # Check if response includes any of the terms
    def includes_any?(response, *terms)
      terms.any? { |term| response.downcase.include?(term.downcase) }
    end

    # Calculate score based on boolean checks
    def score_from_checks(*checks)
      return 0.0 if checks.empty?

      weight = 1.0 / checks.size
      checks.count { |check| check } * weight
    end
  end
end
