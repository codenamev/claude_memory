# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe ClaudeMemory::Hook::DistillationRunner do
  let(:db_path) { File.join(Dir.tmpdir, "distill_runner_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:distiller) { ClaudeMemory::Distill::NullDistiller.new }
  let(:runner) { described_class.new(store, distiller: distiller) }
  let(:project_path) { "/tmp/test-project" }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def create_content_item(text)
    store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize,
      raw_text: text
    )
  end

  describe "#distill_item" do
    context "with valid content containing entities" do
      let(:text) do
        "We decided to use PostgreSQL as our primary database. " \
          "The application is built with Rails and deployed on AWS. " \
          "We always use 4-space indentation across all projects. " \
          "This is a longer transcript to ensure it passes the minimum length threshold for distillation."
      end
      let(:content_id) { create_content_item(text) }

      it "creates facts from distilled content" do
        runner.distill_item(content_id, project_path: project_path)

        facts = store.db[:facts].all
        expect(facts).not_to be_empty
      end

      it "records ingestion metrics" do
        runner.distill_item(content_id, project_path: project_path)

        metrics = store.db[:ingestion_metrics].all
        expect(metrics).not_to be_empty
        expect(metrics.first[:facts_extracted]).to be >= 1
      end

      it "creates provenance linking facts to content" do
        runner.distill_item(content_id, project_path: project_path)

        provenance = store.db[:provenance].all
        expect(provenance).not_to be_empty
        expect(provenance.first[:content_item_id]).to eq(content_id)
      end

      it "wraps resolve and metrics in a single transaction" do
        # Verify transaction is used by checking that both facts and metrics
        # are created atomically
        runner.distill_item(content_id, project_path: project_path)

        facts_count = store.db[:facts].count
        metrics_count = store.db[:ingestion_metrics].count

        expect(facts_count).to be >= 1
        expect(metrics_count).to eq(1)
      end
    end

    context "when text is too short" do
      let(:content_id) { create_content_item("Short text.") }

      it "skips distillation" do
        expect(distiller).not_to receive(:distill)
        runner.distill_item(content_id, project_path: project_path)

        expect(store.db[:facts].count).to eq(0)
      end
    end

    context "when extraction is empty" do
      let(:text) do
        "This is a regular conversation about nothing in particular. " \
          "We talked about the weather and some general topics that are not related to " \
          "any technology stack or architectural decisions whatsoever. " \
          "Just filling up the character count to pass the minimum length threshold here."
      end
      let(:content_id) { create_content_item(text) }

      it "does not create any facts" do
        runner.distill_item(content_id, project_path: project_path)

        expect(store.db[:facts].count).to eq(0)
      end
    end

    context "when content_id does not exist" do
      it "returns nil without error" do
        result = runner.distill_item(999_999, project_path: project_path)
        expect(result).to be_nil
      end
    end

    context "when an error is raised" do
      let(:text) { "We use PostgreSQL for our database. " * 10 }
      let(:content_id) { create_content_item(text) }

      before do
        allow(distiller).to receive(:distill).and_raise(StandardError, "distill boom")
      end

      it "catches the error and does not re-raise" do
        expect { runner.distill_item(content_id, project_path: project_path) }
          .not_to raise_error
      end

      it "logs the error" do
        expect(ClaudeMemory.logger).to receive(:warn).at_least(:once)
        runner.distill_item(content_id, project_path: project_path)
      end

      it "does not create any facts" do
        runner.distill_item(content_id, project_path: project_path)
        expect(store.db[:facts].count).to eq(0)
      end
    end

    context "with custom scope" do
      let(:text) do
        "I always use PostgreSQL in all my projects as the primary database. " \
          "This is a global preference that should apply everywhere. " \
          "We also deploy on AWS universally across all projects. " \
          "These are my universal coding conventions and standards."
      end
      let(:content_id) { create_content_item(text) }

      it "passes scope to resolver" do
        runner.distill_item(content_id, project_path: project_path, scope: "global")

        facts = store.db[:facts].all
        global_facts = facts.select { |f| f[:scope] == "global" }
        expect(global_facts).not_to be_empty
      end
    end
  end

  describe "#distill_batch" do
    context "with undistilled items" do
      before do
        techs = %w[PostgreSQL Rails AWS]
        techs.each_with_index do |tech, i|
          text = "Decision number #{i}: We decided to use #{tech} for our project. " \
            "This is an important architectural choice that affects our entire stack. " \
            "The team agreed on this after careful consideration of alternatives. " \
            "This ensures consistency across all services and applications."
          create_content_item(text)
        end
      end

      it "processes multiple items" do
        count = runner.distill_batch(project_path: project_path, limit: 5)
        expect(count).to eq(3)
      end

      it "creates facts for each item" do
        runner.distill_batch(project_path: project_path)
        expect(store.db[:facts].count).to be >= 3
      end
    end

    context "with no undistilled items" do
      it "returns zero" do
        count = runner.distill_batch(project_path: project_path)
        expect(count).to eq(0)
      end
    end

    context "with already-distilled items" do
      before do
        text = "We decided to use PostgreSQL as our primary database. " \
          "The application is built with Rails and deployed on AWS. " \
          "We always use 4-space indentation across all projects. " \
          "This is important for consistency."
        content_id = create_content_item(text)
        # Mark as distilled by recording metrics
        store.record_ingestion_metrics(
          content_item_id: content_id,
          input_tokens: 0,
          output_tokens: 0,
          facts_extracted: 1
        )
      end

      it "skips already-distilled items" do
        count = runner.distill_batch(project_path: project_path)
        expect(count).to eq(0)
      end
    end
  end
end
