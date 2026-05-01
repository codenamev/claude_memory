# frozen_string_literal: true

require "stringio"

RSpec.describe ClaudeMemory::Deprecations do
  let(:output) { StringIO.new }

  before { described_class.reset! }
  after do
    described_class.reset!
    ENV.delete(described_class::ENV_OPT_OUT)
  end

  describe ".warn" do
    it "emits a basic deprecation message to the given output" do
      result = described_class.warn(name: "Recall#legacy_query", output: output)

      expect(result).to be true
      msg = output.string
      expect(msg).to include("[ClaudeMemory] DEPRECATION")
      expect(msg).to include("Recall#legacy_query is deprecated")
      expect(msg).to match(/called from .+:\d+/)
    end

    it "includes the replacement when provided" do
      described_class.warn(name: "old_method", replacement: "new_method", output: output)
      expect(output.string).to include("use new_method instead")
    end

    it "includes the removed_in version when provided" do
      described_class.warn(name: "old_flag", removed_in: "1.0.0", output: output)
      expect(output.string).to include("scheduled for removal in 1.0.0")
    end

    it "appends free-form message text when provided" do
      described_class.warn(
        name: "subtle_method",
        replacement: "new_method",
        message: "Pass `mode: :legacy` to migrate cleanly.",
        output: output
      )
      expect(output.string).to include("Pass `mode: :legacy` to migrate cleanly.")
    end

    it "combines all fields in a single readable message" do
      described_class.warn(
        name: "Recall#legacy_query",
        replacement: "Recall#query",
        removed_in: "1.0.0",
        message: "Pass mode: :legacy.",
        output: output
      )
      msg = output.string
      expect(msg).to include("Recall#legacy_query is deprecated")
      expect(msg).to include("scheduled for removal in 1.0.0")
      expect(msg).to include("use Recall#query instead")
      expect(msg).to include("Pass mode: :legacy.")
    end

    it "dedupes the same name+location pair within a process" do
      caller = "fake.rb:42"
      first = described_class.warn(name: "x", caller_location: caller, output: output)
      second = described_class.warn(name: "x", caller_location: caller, output: output)

      expect(first).to be true
      expect(second).to be false
      expect(output.string.scan("DEPRECATION").size).to eq(1)
    end

    it "warns again from a different call site for the same name" do
      first = described_class.warn(name: "x", caller_location: "a.rb:1", output: output)
      second = described_class.warn(name: "x", caller_location: "b.rb:2", output: output)

      expect(first).to be true
      expect(second).to be true
      expect(output.string.scan("DEPRECATION").size).to eq(2)
    end

    it "warns again for different names from the same call site" do
      caller = "shared.rb:99"
      described_class.warn(name: "alpha", caller_location: caller, output: output)
      described_class.warn(name: "beta", caller_location: caller, output: output)

      expect(output.string.scan("DEPRECATION").size).to eq(2)
    end

    it "is silenced by CLAUDE_MEMORY_NO_DEPRECATIONS=1" do
      ENV[described_class::ENV_OPT_OUT] = "1"
      result = described_class.warn(name: "anything", output: output)

      expect(result).to be false
      expect(output.string).to be_empty
    end

    it "does not silence when the env var is set to anything other than '1'" do
      ENV[described_class::ENV_OPT_OUT] = "true"
      result = described_class.warn(name: "x", output: output)

      expect(result).to be true
    end

    it "derives caller_location from caller_locations when not overridden" do
      described_class.warn(name: "auto_loc", output: output)
      # The actual caller is this spec file. Verify the format includes
      # a path:line pattern, without depending on absolute path content.
      expect(output.string).to match(/called from .+\.rb:\d+/)
    end
  end

  describe ".reset!" do
    it "wipes the dedupe state so the same call can re-warn" do
      caller = "x.rb:1"
      described_class.warn(name: "x", caller_location: caller, output: output)
      described_class.reset!
      result = described_class.warn(name: "x", caller_location: caller, output: output)

      expect(result).to be true
      expect(output.string.scan("DEPRECATION").size).to eq(2)
    end
  end
end
