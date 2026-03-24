# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe "Undistilled MCP tools" do
  let(:tmpdir) { Dir.mktmpdir("undistilled_test_#{Process.pid}") }
  let(:global_db) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db) { File.join(tmpdir, "project.sqlite3") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db,
      project_db_path: project_db
    )
  end
  let(:tools) { ClaudeMemory::MCP::Tools.new(manager) }

  before do
    manager.ensure_both!
  end

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def create_content_item(store, text, occurred_at: nil)
    store.upsert_content_item(
      source: "test",
      session_id: "sess-#{rand(10000)}",
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize,
      raw_text: text,
      occurred_at: occurred_at || Time.now.utc.iso8601
    )
  end

  describe "SQLiteStore#undistilled_content_items" do
    let(:store) { manager.project_store }

    it "returns content items without ingestion metrics" do
      text = "A" * 300
      id = create_content_item(store, text)

      items = store.undistilled_content_items
      expect(items.map { |i| i[:id] }).to include(id)
    end

    it "excludes content items that have ingestion metrics" do
      text = "B" * 300
      id = create_content_item(store, text)
      store.record_ingestion_metrics(
        content_item_id: id,
        input_tokens: 0,
        output_tokens: 0,
        facts_extracted: 2
      )

      items = store.undistilled_content_items
      expect(items.map { |i| i[:id] }).not_to include(id)
    end

    it "respects min_length filter" do
      short_id = create_content_item(store, "short text")
      long_id = create_content_item(store, "C" * 300)

      items = store.undistilled_content_items(min_length: 200)
      ids = items.map { |i| i[:id] }
      expect(ids).to include(long_id)
      expect(ids).not_to include(short_id)
    end

    it "respects limit" do
      5.times { |i| create_content_item(store, "D#{i}" * 200) }

      items = store.undistilled_content_items(limit: 2)
      expect(items.size).to eq(2)
    end

    it "orders by occurred_at descending" do
      old_id = create_content_item(store, "E" * 300, occurred_at: "2025-01-01T00:00:00Z")
      new_id = create_content_item(store, "F" * 300, occurred_at: "2026-03-24T00:00:00Z")

      items = store.undistilled_content_items
      expect(items.first[:id]).to eq(new_id)
      expect(items.last[:id]).to eq(old_id)
    end
  end

  describe "memory.undistilled MCP tool" do
    it "returns undistilled content items" do
      create_content_item(manager.project_store, "G" * 300)

      result = tools.call("memory.undistilled", {})

      expect(result[:count]).to eq(1)
      expect(result[:items].first[:content_item_id]).to be_a(Integer)
      expect(result[:items].first[:raw_text]).to be_a(String)
      expect(result[:items].first[:occurred_ago]).to be_a(String)
    end

    it "returns empty when all items are distilled" do
      id = create_content_item(manager.project_store, "H" * 300)
      manager.project_store.record_ingestion_metrics(
        content_item_id: id,
        input_tokens: 0,
        output_tokens: 0,
        facts_extracted: 1
      )

      result = tools.call("memory.undistilled", {})

      expect(result[:count]).to eq(0)
      expect(result[:items]).to be_empty
    end

    it "truncates raw_text to 2000 chars" do
      create_content_item(manager.project_store, "I" * 5000)

      result = tools.call("memory.undistilled", {})

      expect(result[:items].first[:raw_text].length).to be <= 2003 # 2000 + "..."
    end

    it "accepts limit and min_length parameters" do
      3.times { |i| create_content_item(manager.project_store, "J#{i}" * 200) }

      result = tools.call("memory.undistilled", {"limit" => 1, "min_length" => 100})

      expect(result[:count]).to eq(1)
    end
  end

  describe "memory.mark_distilled MCP tool" do
    it "marks a content item as distilled" do
      id = create_content_item(manager.project_store, "K" * 300)

      result = tools.call("memory.mark_distilled", {
        "content_item_id" => id,
        "facts_extracted" => 3
      })

      expect(result[:success]).to be true
      expect(result[:content_item_id]).to eq(id)
      expect(result[:facts_extracted]).to eq(3)

      # Verify it's now excluded from undistilled
      undistilled = tools.call("memory.undistilled", {})
      expect(undistilled[:items].map { |i| i[:content_item_id] }).not_to include(id)
    end

    it "defaults facts_extracted to 0" do
      id = create_content_item(manager.project_store, "L" * 300)

      result = tools.call("memory.mark_distilled", {"content_item_id" => id})

      expect(result[:success]).to be true
      expect(result[:facts_extracted]).to eq(0)
    end

    it "returns error for non-existent content item" do
      result = tools.call("memory.mark_distilled", {"content_item_id" => 99999})

      expect(result[:error]).to include("not found")
    end
  end

  describe "ContextInjector distillation prompt" do
    let(:injector) { ClaudeMemory::Hook::ContextInjector.new(manager) }

    it "includes distillation prompt when undistilled items exist" do
      create_content_item(manager.project_store, "M" * 300)

      context = injector.generate_context

      expect(context).to include("Pending Knowledge Extraction")
      expect(context).to include("memory.store_extraction")
      expect(context).to include("memory.mark_distilled")
      expect(context).to include("Content Item")
    end

    it "omits distillation prompt when all items are distilled" do
      id = create_content_item(manager.project_store, "N" * 300)
      manager.project_store.record_ingestion_metrics(
        content_item_id: id,
        input_tokens: 0,
        output_tokens: 0,
        facts_extracted: 1
      )

      context = injector.generate_context

      # Context may be nil if no facts exist either
      if context
        expect(context).not_to include("Pending Knowledge Extraction")
      end
    end

    it "truncates raw text to 1500 chars per item" do
      create_content_item(manager.project_store, "O" * 3000)

      context = injector.generate_context

      # Find the content item section and verify truncation
      expect(context).to include("...")
      # The raw text portion should not exceed 1500 + "..." length
      lines = context.split("\n")
      content_line = lines.find { |l| l.start_with?("O") }
      expect(content_line.length).to be <= 1503 if content_line
    end
  end

  describe "tool definitions" do
    it "includes memory.undistilled" do
      defs = tools.definitions
      tool = defs.find { |d| d[:name] == "memory.undistilled" }
      expect(tool).not_to be_nil
      expect(tool[:annotations][:readOnlyHint]).to be true
    end

    it "includes memory.mark_distilled" do
      defs = tools.definitions
      tool = defs.find { |d| d[:name] == "memory.mark_distilled" }
      expect(tool).not_to be_nil
      expect(tool[:annotations][:idempotentHint]).to be true
      expect(tool[:inputSchema][:required]).to include("content_item_id")
    end
  end
end
