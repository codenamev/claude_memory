# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "digest"

RSpec.describe ClaudeMemory::Hook::Handler, "distillation integration" do
  let(:db_path) { File.join(Dir.tmpdir, "hook_distill_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:handler) { described_class.new(store) }
  let(:transcript_path) { File.join(Dir.tmpdir, "hook_distill_transcript_#{Process.pid}.jsonl") }
  let(:project_path) { "/tmp/test-project" }

  let(:payload) do
    {
      "hook_type" => "Stop",
      "session_id" => "session-distill-123",
      "transcript_path" => transcript_path,
      "project_path" => project_path
    }
  end

  after do
    store.close
    FileUtils.rm_f(db_path)
    FileUtils.rm_f(transcript_path)
  end

  describe "distill_content after ingest" do
    context "when ingested content contains recognizable entities" do
      before do
        # Content long enough (>= 200 chars) with recognizable entities
        content = "We decided to use PostgreSQL as our primary database. " \
          "The application is built with Rails and deployed on AWS. " \
          "We always use 4-space indentation across all projects. " \
          "This is a longer transcript to ensure it passes the minimum length threshold for distillation."
        File.write(transcript_path, content)
      end

      it "creates facts from distilled content" do
        result = handler.ingest(payload)

        expect(result[:status]).to eq(:ingested)

        # Check that facts were created by the distiller + resolver
        facts = store.db[:facts].all
        expect(facts).not_to be_empty
      end

      it "creates entities from distilled content" do
        handler.ingest(payload)

        entities = store.db[:entities].all
        entity_names = entities.map { |e| e[:canonical_name] }
        expect(entity_names).to include("postgresql")
      end

      it "records ingestion metrics" do
        handler.ingest(payload)

        metrics = store.db[:ingestion_metrics].all
        expect(metrics).not_to be_empty
        expect(metrics.first[:input_tokens]).to eq(0)
        expect(metrics.first[:output_tokens]).to eq(0)
        expect(metrics.first[:facts_extracted]).to be >= 1
      end

      it "creates provenance linking facts to content" do
        result = handler.ingest(payload)

        provenance = store.db[:provenance].all
        expect(provenance).not_to be_empty
        expect(provenance.first[:content_item_id]).to eq(result[:content_id])
      end
    end

    context "when content is too short for distillation" do
      before do
        File.write(transcript_path, "Short text here.")
      end

      it "does not create any facts" do
        handler.ingest(payload)

        facts = store.db[:facts].all
        expect(facts).to be_empty
      end

      it "does not record ingestion metrics" do
        handler.ingest(payload)

        metrics = store.db[:ingestion_metrics].all
        expect(metrics).to be_empty
      end
    end

    context "when content has no recognizable entities" do
      before do
        content = "This is a regular conversation about nothing in particular. " \
          "We talked about the weather and some general topics that are not related to " \
          "any technology stack or architectural decisions whatsoever. " \
          "Just filling up the character count to pass the minimum length threshold here."
        File.write(transcript_path, content)
      end

      it "does not create any facts" do
        handler.ingest(payload)

        facts = store.db[:facts].all
        expect(facts).to be_empty
      end
    end

    context "when distillation raises an error" do
      before do
        content = "We use PostgreSQL for our database. " * 10
        File.write(transcript_path, content)

        allow_any_instance_of(ClaudeMemory::Distill::NullDistiller)
          .to receive(:distill).and_raise(StandardError, "distill boom")
      end

      it "still returns the ingest result successfully" do
        result = handler.ingest(payload)

        expect(result[:status]).to eq(:ingested)
        expect(result[:content_id]).not_to be_nil
      end

      it "does not create any facts" do
        handler.ingest(payload)

        facts = store.db[:facts].all
        expect(facts).to be_empty
      end
    end

    context "when ingest returns non-ingested status" do
      before do
        File.write(transcript_path, "test content\n")
      end

      it "does not attempt distillation on second ingest" do
        handler.ingest(payload)

        expect_any_instance_of(ClaudeMemory::Distill::NullDistiller)
          .not_to receive(:distill)

        # Second ingest returns :skipped (no change)
        handler.ingest(payload)
      end
    end
  end
end
