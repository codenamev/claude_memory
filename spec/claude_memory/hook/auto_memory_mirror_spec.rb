# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::Hook::AutoMemoryMirror do
  let(:tmpdir) { Dir.mktmpdir("auto_memory_mirror_#{Process.pid}") }
  let(:auto_memory_dir) { File.join(tmpdir, "memory") }
  let(:state_file) { File.join(tmpdir, ".claude", "auto_memory_mirror.json") }
  let(:mirror) { described_class.new(auto_memory_dir: auto_memory_dir, state_file: state_file) }

  before { FileUtils.mkdir_p(auto_memory_dir) }
  after { FileUtils.rm_rf(tmpdir) }

  def write_memory(name, body)
    path = File.join(auto_memory_dir, name)
    File.write(path, body)
    path
  end

  describe ".default_dir" do
    it "maps project path to slug via tr('/','-')" do
      dir = described_class.default_dir("/Users/me/src/app", "/home/me/.claude")
      expect(dir).to eq("/home/me/.claude/projects/-Users-me-src-app/memory")
    end
  end

  describe ".default_state_file" do
    it "places state under .claude in the project dir" do
      expect(described_class.default_state_file("/Users/me/src/app"))
        .to eq("/Users/me/src/app/.claude/auto_memory_mirror.json")
    end
  end

  describe "#pending_candidates" do
    context "with no auto-memory directory" do
      it "returns [] gracefully" do
        FileUtils.rm_rf(auto_memory_dir)
        expect(mirror.pending_candidates).to eq([])
      end
    end

    context "on initial scan" do
      before do
        write_memory("MEMORY.md", "# Memory index\nsome prose")
        write_memory("gotcha_foo.md", "gotcha body")
      end

      it "returns all markdown files as candidates" do
        results = mirror.pending_candidates
        names = results.map { |c| c[:name] }
        expect(names).to contain_exactly("MEMORY.md", "gotcha_foo.md")
      end

      it "attaches content and signature" do
        candidate = mirror.pending_candidates.find { |c| c[:name] == "gotcha_foo.md" }
        expect(candidate[:content]).to include("gotcha body")
        expect(candidate[:signature][:md5]).to match(/\A[a-f0-9]{32}\z/)
        expect(candidate[:signature][:mtime]).to be_a(Integer)
      end

      it "respects the limit keyword" do
        3.times { |i| write_memory("extra_#{i}.md", "body #{i}") }
        expect(mirror.pending_candidates(limit: 2).size).to eq(2)
      end
    end

    context "after commit" do
      before do
        write_memory("gotcha_a.md", "gotcha a body")
        write_memory("gotcha_b.md", "gotcha b body")
      end

      it "skips unchanged files on re-run" do
        initial = mirror.pending_candidates
        mirror.commit(initial)

        expect(mirror.pending_candidates).to eq([])
      end

      it "re-emits only changed files" do
        initial = mirror.pending_candidates
        mirror.commit(initial)

        write_memory("gotcha_a.md", "gotcha a body UPDATED")

        pending = mirror.pending_candidates
        names = pending.map { |c| c[:name] }
        expect(names).to eq(["gotcha_a.md"])
      end

      it "emits new files added after the last commit" do
        mirror.commit(mirror.pending_candidates)

        write_memory("gotcha_c.md", "new one")

        pending = mirror.pending_candidates
        expect(pending.map { |c| c[:name] }).to eq(["gotcha_c.md"])
      end
    end

    context "with a malformed state file" do
      before do
        write_memory("gotcha_a.md", "body")
        FileUtils.mkdir_p(File.dirname(state_file))
        File.write(state_file, "{not json")
      end

      it "falls back to emitting everything" do
        expect(mirror.pending_candidates.map { |c| c[:name] }).to eq(["gotcha_a.md"])
      end
    end
  end

  describe "#commit" do
    before { write_memory("gotcha_a.md", "body") }

    it "creates the .claude directory if missing" do
      mirror.commit(mirror.pending_candidates)
      expect(File.exist?(state_file)).to be true
    end

    it "is a no-op on empty candidate list" do
      mirror.commit([])
      expect(File.exist?(state_file)).to be false
    end

    it "persists md5 + mtime per file" do
      mirror.commit(mirror.pending_candidates)
      parsed = JSON.parse(File.read(state_file))
      expect(parsed["gotcha_a.md"]).to include("md5", "mtime")
    end
  end
end
