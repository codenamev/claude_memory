# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 007: Add Ingestion Metrics" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    # Run up to migration 006 first
    Sequel::Migrator.run(db, migrations_path, target: 6)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    expect(db.tables).to include(:ingestion_metrics)
  end

  it "creates ingestion_metrics table with correct columns" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    columns = db.schema(:ingestion_metrics).map(&:first)
    expect(columns).to include(
      :id,
      :content_item_id,
      :input_tokens,
      :output_tokens,
      :facts_extracted,
      :created_at
    )
  end

  it "creates ingestion_metrics indexes" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    indexes = db.indexes(:ingestion_metrics)
    expect(indexes.keys).to include(
      :idx_ingestion_metrics_content_item,
      :idx_ingestion_metrics_created_at
    )
  end

  it "allows tracking token usage and facts extracted" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    content_item_id = db[:content_items].insert(
      source: "test.jsonl",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 1000
    )

    metric_id = db[:ingestion_metrics].insert(
      content_item_id: content_item_id,
      input_tokens: 2500,
      output_tokens: 800,
      facts_extracted: 15,
      created_at: Time.now.utc.iso8601
    )

    metric = db[:ingestion_metrics].where(id: metric_id).first
    expect(metric[:input_tokens]).to eq(2500)
    expect(metric[:output_tokens]).to eq(800)
    expect(metric[:facts_extracted]).to eq(15)

    # Calculate cost per fact
    total_tokens = metric[:input_tokens] + metric[:output_tokens]
    tokens_per_fact = total_tokens.to_f / metric[:facts_extracted]
    expect(tokens_per_fact).to be_within(0.1).of(220.0)
  end

  it "allows querying metrics by content_item" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    content_item_id = db[:content_items].insert(
      source: "test.jsonl",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 1000
    )

    db[:ingestion_metrics].insert(
      content_item_id: content_item_id,
      input_tokens: 1000,
      output_tokens: 500,
      facts_extracted: 10,
      created_at: Time.now.utc.iso8601
    )

    metrics = db[:ingestion_metrics].where(content_item_id: content_item_id).all
    expect(metrics.length).to eq(1)
    expect(metrics.first[:facts_extracted]).to eq(10)
  end

  it "allows calculating aggregate statistics" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    # Create multiple content items and metrics
    3.times do |i|
      content_item_id = db[:content_items].insert(
        source: "test_#{i}.jsonl",
        ingested_at: Time.now.utc.iso8601,
        text_hash: "hash_#{i}",
        byte_len: 1000 * (i + 1)
      )

      db[:ingestion_metrics].insert(
        content_item_id: content_item_id,
        input_tokens: 1000 * (i + 1),
        output_tokens: 500 * (i + 1),
        facts_extracted: 10 * (i + 1),
        created_at: Time.now.utc.iso8601
      )
    end

    # Calculate totals
    metrics = db[:ingestion_metrics].all
    total_input = metrics.sum { |m| m[:input_tokens] }
    total_output = metrics.sum { |m| m[:output_tokens] }
    total_facts = metrics.sum { |m| m[:facts_extracted] }

    expect(total_input).to eq(6000)  # 1000 + 2000 + 3000
    expect(total_output).to eq(3000)  # 500 + 1000 + 1500
    expect(total_facts).to eq(60)     # 10 + 20 + 30

    average_tokens_per_fact = (total_input + total_output).to_f / total_facts
    expect(average_tokens_per_fact).to eq(150.0)
  end

  it "allows querying metrics by date range" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    content_item_id = db[:content_items].insert(
      source: "test.jsonl",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 1000
    )

    # Old metric
    db[:ingestion_metrics].insert(
      content_item_id: content_item_id,
      input_tokens: 1000,
      facts_extracted: 10,
      created_at: "2026-01-01T12:00:00Z"
    )

    # Recent metric
    db[:ingestion_metrics].insert(
      content_item_id: content_item_id,
      input_tokens: 2000,
      facts_extracted: 20,
      created_at: "2026-01-27T12:00:00Z"
    )

    cutoff = "2026-01-15T00:00:00Z"
    recent_metrics = db[:ingestion_metrics].where { created_at >= cutoff }.all

    expect(recent_metrics.length).to eq(1)
    expect(recent_metrics.first[:facts_extracted]).to eq(20)
  end

  it "allows tracking failed distillations with zero facts" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    content_item_id = db[:content_items].insert(
      source: "test.jsonl",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 1000
    )

    # Record a distillation attempt that extracted no facts
    metric_id = db[:ingestion_metrics].insert(
      content_item_id: content_item_id,
      input_tokens: 500,
      output_tokens: 100,
      facts_extracted: 0,
      created_at: Time.now.utc.iso8601
    )

    metric = db[:ingestion_metrics].where(id: metric_id).first
    expect(metric[:facts_extracted]).to eq(0)
    expect(metric[:input_tokens]).to eq(500)  # Tokens were spent even though no facts extracted
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 7)

    expect(db.tables).to include(:ingestion_metrics)

    Sequel::Migrator.run(db, migrations_path, target: 6)

    expect(db.tables).not_to include(:ingestion_metrics)
  end
end
