# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Audit::Checks, "observation layer checks" do
  let(:project_db) { File.join(Dir.tmpdir, "audit_obs_project_#{Process.pid}.sqlite3") }
  let(:global_db) { File.join(Dir.tmpdir, "audit_obs_global_#{Process.pid}.sqlite3") }
  let(:manager) { ClaudeMemory::Store::StoreManager.new(project_db_path: project_db, global_db_path: global_db) }
  let(:store) { manager.project_store }

  before { manager.ensure_project! }

  after do
    manager.close
    FileUtils.rm_f(project_db)
    FileUtils.rm_f(global_db)
  end

  def content_item(text: "some transcript chunk")
    store.upsert_content_item(
      source: "transcript",
      raw_text: text,
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize
    )
  end

  def fact(predicate: "decision", object: "we chose X because Y", status: "active")
    entity_id = store.find_or_create_entity(type: "repo", name: "repo")
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object,
      status: status,
      scope: "project"
    )
  end

  describe ".orphaned_observations (C011)" do
    it "passes when source_content_item_id points at a real content item" do
      cid = content_item
      store.insert_observation(body: "did a thing", source_content_item_id: cid)

      expect(described_class.orphaned_observations(manager)).to be_empty
    end

    it "passes when source_content_item_id is nil" do
      store.insert_observation(body: "did a thing", source_content_item_id: nil)

      expect(described_class.orphaned_observations(manager)).to be_empty
    end

    it "flags observations pointing at a non-existent content item" do
      obs = store.insert_observation(body: "orphaned", source_content_item_id: 999_999)

      findings = described_class.orphaned_observations(manager)
      expect(findings.size).to eq(1)
      expect(findings.first.id).to eq("C011")
      expect(findings.first.severity).to eq(:warn)
      expect(findings.first.fact_ids).to include(obs)
    end
  end

  describe ".observation_promotion_consistency (C012)" do
    it "passes when a promoted observation points at an active fact" do
      fid = fact
      obs = store.insert_observation(body: "corroborated thing")
      store.mark_observation_promoted(obs, fact_id: fid)

      expect(described_class.observation_promotion_consistency(manager)).to be_empty
    end

    it "flags promoted_at set without promoted_fact_id" do
      obs = store.insert_observation(body: "half-promoted")
      store.observations.where(id: obs).update(promoted_at: Time.now.utc.iso8601)

      findings = described_class.observation_promotion_consistency(manager)
      expect(findings.first.id).to eq("C012")
      expect(findings.first.severity).to eq(:error)
      expect(findings.first.fact_ids).to include(obs)
    end

    it "flags promoted_fact_id pointing at a non-existent fact" do
      obs = store.insert_observation(body: "dangling promotion")
      store.mark_observation_promoted(obs, fact_id: 999_999)

      findings = described_class.observation_promotion_consistency(manager)
      expect(findings.first.id).to eq("C012")
      expect(findings.first.fact_ids).to include(obs)
    end

    it "flags promotion into a non-active fact" do
      fid = fact(status: "rejected")
      obs = store.insert_observation(body: "promoted into rejected fact")
      store.mark_observation_promoted(obs, fact_id: fid)

      findings = described_class.observation_promotion_consistency(manager)
      expect(findings.first.id).to eq("C012")
      expect(findings.first.fact_ids).to include(obs)
    end

    it "flags promoted_fact_id set without promoted_at" do
      fid = fact
      obs = store.insert_observation(body: "missing timestamp")
      store.observations.where(id: obs).update(promoted_fact_id: fid)

      findings = described_class.observation_promotion_consistency(manager)
      expect(findings.first.id).to eq("C012")
      expect(findings.first.fact_ids).to include(obs)
    end
  end

  describe ".observation_tombstone_chain (C013)" do
    it "passes for a valid tombstone pointing at an existing keeper" do
      keeper = store.insert_observation(body: "keeper")
      loser = store.insert_observation(body: "loser")
      store.tombstone_observation(loser, into_id: keeper)

      expect(described_class.observation_tombstone_chain(manager)).to be_empty
    end

    it "flags consolidated_into pointing at a missing observation" do
      loser = store.insert_observation(body: "loser")
      store.tombstone_observation(loser, into_id: 999_999)

      findings = described_class.observation_tombstone_chain(manager)
      expect(findings.first.id).to eq("C013")
      expect(findings.first.severity).to eq(:error)
      expect(findings.first.fact_ids).to include(loser)
    end

    it "flags a self-link" do
      obs = store.insert_observation(body: "self-referential")
      store.observations.where(id: obs).update(status: "consolidated", consolidated_into: obs)

      findings = described_class.observation_tombstone_chain(manager)
      expect(findings.first.id).to eq("C013")
      expect(findings.first.fact_ids).to include(obs)
    end

    it "flags an active observation that also carries a consolidated_into target" do
      keeper = store.insert_observation(body: "keeper")
      obs = store.insert_observation(body: "active but tombstoned")
      store.observations.where(id: obs).update(consolidated_into: keeper)

      findings = described_class.observation_tombstone_chain(manager)
      expect(findings.first.id).to eq("C013")
      expect(findings.first.fact_ids).to include(obs)
    end

    it "flags a consolidated observation with no keeper link" do
      obs = store.insert_observation(body: "consolidated without target")
      store.observations.where(id: obs).update(status: "consolidated")

      findings = described_class.observation_tombstone_chain(manager)
      expect(findings.first.id).to eq("C013")
      expect(findings.first.fact_ids).to include(obs)
    end
  end

  describe ".observation_status_corroboration (C014)" do
    it "passes for fresh active observations" do
      store.insert_observation(body: "fresh observation")

      expect(described_class.observation_status_corroboration(manager)).to be_empty
    end

    it "flags an unknown status" do
      obs = store.insert_observation(body: "weird status")
      store.observations.where(id: obs).update(status: "bogus")

      findings = described_class.observation_status_corroboration(manager)
      expect(findings.first.id).to eq("C014")
      expect(findings.first.severity).to eq(:warn)
      expect(findings.first.fact_ids).to include(obs)
    end

    it "flags corroboration_count below 1" do
      obs = store.insert_observation(body: "zero sightings")
      store.observations.where(id: obs).update(corroboration_count: 0)

      findings = described_class.observation_status_corroboration(manager)
      expect(findings.first.id).to eq("C014")
      expect(findings.first.fact_ids).to include(obs)
    end
  end

  describe "wired into the Runner" do
    it "runs the observation checks as part of a full audit" do
      obs = store.insert_observation(body: "orphan", source_content_item_id: 999_999)

      result = ClaudeMemory::Audit::Runner.new(manager: manager).run
      c011 = result.findings.find { |f| f.id == "C011" }
      expect(c011).not_to be_nil
      expect(c011.fact_ids).to include(obs)
    end
  end
end
