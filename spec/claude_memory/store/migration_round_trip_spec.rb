# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "sequel"
require "sequel/extensions/migration"

# Round-trip the v18 migration: up to 18 with seeded data, then down to 17,
# then back up to 18. Locks down that the additive prompt_id column on
# activity_events and the three otel_* tables migrate cleanly forward and
# backward.
RSpec.describe "Schema 17 → 18 round trip" do
  let(:tmpdir) { Dir.mktmpdir("migration_round_trip_#{Process.pid}") }
  let(:db_path) { File.join(tmpdir, "memory.sqlite3") }
  let(:migrations_path) { File.expand_path("../../../db/migrations", __dir__) }

  after { FileUtils.rm_rf(tmpdir) }

  it "creates the otel_* tables on up" do
    store = ClaudeMemory::Store::SQLiteStore.new(db_path)
    expect(store.db.table_exists?(:otel_metrics)).to be true
    expect(store.db.table_exists?(:otel_events)).to be true
    expect(store.db.table_exists?(:otel_traces)).to be true
    expect(store.db.schema(:activity_events).map(&:first)).to include(:prompt_id)
    store.close
  end

  it "migrates back to 17 cleanly" do
    store = ClaudeMemory::Store::SQLiteStore.new(db_path)
    store.insert_otel_metric(name: "x", value_type: "int", value_int: 1, recorded_at: Time.now.utc.iso8601)
    store.close

    Sequel.connect("extralite:#{db_path}") do |db|
      Sequel::Migrator.run(db, migrations_path, target: 17)
      expect(db.table_exists?(:otel_metrics)).to be false
      expect(db.table_exists?(:otel_events)).to be false
      expect(db.table_exists?(:otel_traces)).to be false
      expect(db.schema(:activity_events).map(&:first)).not_to include(:prompt_id)
    end
  end

  it "migrates back up to 18 after a downgrade with no errors" do
    ClaudeMemory::Store::SQLiteStore.new(db_path).close
    Sequel.connect("extralite:#{db_path}") do |db|
      Sequel::Migrator.run(db, migrations_path, target: 17)
      Sequel::Migrator.run(db, migrations_path, target: 18)
      expect(db.table_exists?(:otel_metrics)).to be true
      expect(db.schema(:activity_events).map(&:first)).to include(:prompt_id)
    end
  end
end
