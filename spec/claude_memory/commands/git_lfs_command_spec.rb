# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::GitLfsCommand do
  let(:tmpdir) { Dir.mktmpdir("git_lfs_test_#{Process.pid}") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  before do
    @original_dir = Dir.pwd
    Dir.chdir(tmpdir)
  end

  after do
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(tmpdir)
  end

  describe "precondition checks" do
    it "fails when not in a git repository" do
      exit_code = command.call([])

      expect(exit_code).to eq(1)
      expect(stderr.string).to include("Not a git repository")
    end

    it "fails when git-lfs is not installed" do
      system("git", "init", out: File::NULL, err: File::NULL)
      allow(command).to receive(:git_lfs_installed?).and_return(false)

      exit_code = command.call([])

      expect(exit_code).to eq(1)
      expect(stderr.string).to include("git-lfs is not installed")
    end
  end

  context "in a git repo with git-lfs available" do
    before do
      system("git", "init", out: File::NULL, err: File::NULL)
      # Skip if git-lfs not available in test environment
      skip "git-lfs not installed" unless system("git", "lfs", "version", out: File::NULL, err: File::NULL)
    end

    it "sets up git-lfs tracking" do
      allow(command).to receive(:compact_project_db)

      exit_code = command.call(["--no-compact"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("git-lfs setup complete!")
      expect(File.exist?(".gitattributes")).to be true
      attrs = File.read(".gitattributes")
      expect(attrs).to include(".claude/memory.sqlite3")
      expect(attrs).to include("filter=lfs")
    end

    it "skips if already tracked" do
      allow(command).to receive(:compact_project_db)
      # Run once to set up
      command.call(["--no-compact"])

      # Run again
      new_stdout = StringIO.new
      cmd2 = described_class.new(stdout: new_stdout, stderr: stderr)
      exit_code = cmd2.call(["--no-compact"])

      expect(exit_code).to eq(0)
      expect(new_stdout.string).to include("already tracking")
    end

    it "removes sqlite3 entries from .gitignore" do
      File.write(".gitignore", <<~GITIGNORE)
        /tmp/
        .claude/memory.sqlite3
        .claude/memory.sqlite3-shm
        .claude/memory.sqlite3-wal
        *.gem
      GITIGNORE
      allow(command).to receive(:compact_project_db)

      command.call(["--no-compact"])

      gitignore = File.read(".gitignore")
      expect(gitignore).not_to include(".claude/memory.sqlite3\n")
      expect(gitignore).to include("/tmp/")
      expect(gitignore).to include("*.gem")
    end

    it "shows next steps" do
      allow(command).to receive(:compact_project_db)

      command.call(["--no-compact"])

      expect(stdout.string).to include("git add .gitattributes")
      expect(stdout.string).to include("git add .claude/memory.sqlite3")
      expect(stdout.string).to include("git commit")
    end

    it "compacts before setup by default" do
      expect(command).to receive(:compact_project_db)

      command.call([])
    end

    it "skips compact with --no-compact" do
      expect(command).not_to receive(:compact_project_db)

      command.call(["--no-compact"])
    end
  end
end
