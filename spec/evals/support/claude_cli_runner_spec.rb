# frozen_string_literal: true

require_relative "claude_cli_runner"
require "tmpdir"

RSpec.describe EvalHelpers::ClaudeCliRunner do
  let(:working_dir) { Dir.mktmpdir("cli-runner-test") }
  let(:runner) { described_class.new(working_dir: working_dir, memory_enabled: true) }

  after do
    FileUtils.rm_rf(working_dir)
  end

  describe "#run" do
    context "with successful CLI execution" do
      let(:text_output) { "This is the response from Claude" }

      before do
        allow(Open3).to receive(:capture2)
          .and_return([text_output, double(success?: true)])
      end

      it "executes claude CLI with correct arguments" do
        runner.run(prompt: "test prompt")

        expect(Open3).to have_received(:capture2) do |*args, **opts|
          expect(args).to include("claude")
          expect(args).to include("-p")
          expect(args).to include("test prompt")
          expect(args).to include("--output-format")
          expect(args).to include("text")
          expect(args).to include("--no-session-persistence")
          expect(args).to include("--max-budget-usd")
          expect(args).to include("0.10")
          expect(opts[:chdir]).to eq(working_dir)
          expect(opts[:err]).to eq(File::NULL)
        end
      end

      it "includes context in prompt when provided" do
        runner.run(prompt: "test prompt", context: "test context")

        expect(Open3).to have_received(:capture2) do |*args, **_opts|
          full_prompt = args.find { |a| a.include?("test context") && a.include?("test prompt") }
          expect(full_prompt).not_to be_nil
        end
      end

      it "returns success hash with parsed content" do
        result = runner.run(prompt: "test")

        expect(result[:success]).to be(true)
        expect(result[:result]).to eq("This is the response from Claude")
        expect(result[:session_id]).to eq("text-mode")
        expect(result[:cost]).to be_a(Float)
      end

      it "estimates cost from text length" do
        result = runner.run(prompt: "test")

        # Should estimate based on output length
        expect(result[:cost]).to be > 0
        expect(result[:cost]).to be < 0.01
      end
    end

    context "with shell reset messages in output" do
      let(:text_output) { "Response text\nShell cwd was reset to /some/path" }

      before do
        allow(Open3).to receive(:capture2)
          .and_return([text_output, double(success?: true)])
      end

      it "filters out shell reset messages" do
        result = runner.run(prompt: "test")

        expect(result[:success]).to be(true)
        expect(result[:result]).to eq("Response text")
      end
    end

    context "with failed CLI execution" do
      before do
        allow(Open3).to receive(:capture2)
          .and_return(["Error: something went wrong", double(success?: false)])
      end

      it "returns failure hash" do
        result = runner.run(prompt: "test")

        expect(result[:success]).to be(false)
        expect(result[:error]).to include("CLI failed")
      end
    end

    context "with exception during execution" do
      before do
        allow(Open3).to receive(:capture2)
          .and_raise(StandardError.new("Network error"))
      end

      it "returns failure hash with error message" do
        result = runner.run(prompt: "test")

        expect(result[:success]).to be(false)
        expect(result[:error]).to eq("Network error")
      end
    end
  end
end

RSpec.describe EvalHelpers::CliRunnerFactory do
  describe ".baseline_runner" do
    it "creates runner with temporary directory" do
      runner = described_class.baseline_runner

      expect(runner).to be_a(EvalHelpers::ClaudeCliRunner)
      expect(runner.instance_variable_get(:@memory_enabled)).to be(false)
    end
  end

  describe ".memory_enabled_runner" do
    it "creates runner with project directory" do
      project_dir = "/path/to/project"
      runner = described_class.memory_enabled_runner(project_dir)

      expect(runner).to be_a(EvalHelpers::ClaudeCliRunner)
      expect(runner.instance_variable_get(:@working_dir)).to eq(project_dir)
      expect(runner.instance_variable_get(:@memory_enabled)).to be(true)
    end
  end
end
