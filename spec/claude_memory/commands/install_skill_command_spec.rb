# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::InstallSkillCommand do
  let(:tmpdir) { Dir.mktmpdir("install_skill_test_#{Process.pid}") }
  let(:home_dir) { File.join(tmpdir, "home") }
  let(:commands_dir) { File.join(home_dir, ".claude", "commands") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  before do
    allow(Dir).to receive(:home).and_return(home_dir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "--list" do
    it "lists available skills" do
      exit_code = command.call(["--list"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("memory-recall")
      expect(stdout.string).to include("Available skills:")
    end
  end

  describe "with no arguments" do
    it "shows available skills" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Available skills:")
    end
  end

  describe "install" do
    it "installs memory-recall skill" do
      exit_code = command.call(["memory-recall"])
      expect(exit_code).to eq(0)

      target = File.join(commands_dir, "memory-recall.md")
      expect(File.exist?(target)).to be true
      expect(File.read(target)).to include("Memory Recall Agent")
      expect(stdout.string).to include("Installed memory-recall")
    end

    it "creates commands directory if missing" do
      expect(Dir.exist?(commands_dir)).to be false
      command.call(["memory-recall"])
      expect(Dir.exist?(commands_dir)).to be true
    end

    it "refuses to overwrite without --force" do
      FileUtils.mkdir_p(commands_dir)
      File.write(File.join(commands_dir, "memory-recall.md"), "existing")

      exit_code = command.call(["memory-recall"])
      expect(exit_code).to eq(1)
      expect(stderr.string).to include("already exists")
    end

    it "overwrites with --force" do
      FileUtils.mkdir_p(commands_dir)
      File.write(File.join(commands_dir, "memory-recall.md"), "existing")

      exit_code = command.call(["memory-recall", "--force"])
      expect(exit_code).to eq(0)
      expect(File.read(File.join(commands_dir, "memory-recall.md"))).to include("Memory Recall Agent")
    end

    it "rejects unknown skill names" do
      exit_code = command.call(["nonexistent"])
      expect(exit_code).to eq(1)
      expect(stderr.string).to include("Unknown skill")
    end
  end

  describe "AVAILABLE_SKILLS" do
    it "has valid file references" do
      described_class::AVAILABLE_SKILLS.each do |name, info|
        source = File.join(described_class::SKILLS_DIR, info[:file])
        expect(File.exist?(source)).to be(true),
          "Skill '#{name}' references missing file: #{source}"
      end
    end
  end
end
