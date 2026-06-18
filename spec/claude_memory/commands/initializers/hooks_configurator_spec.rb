# frozen_string_literal: true

require "stringio"

RSpec.describe ClaudeMemory::Commands::Initializers::HooksConfigurator do
  let(:configurator) { described_class.new(StringIO.new) }

  it "wires the context (reflection) hook into PreCompact alongside ingest + sweep" do
    config = configurator.send(:build_hooks_config, "INGEST", "SWEEP", "NUDGE")
    precompact = config["hooks"]["PreCompact"].first["hooks"].map { |h| h["command"] }

    expect(precompact).to eq(["INGEST", "SWEEP", "claude-memory hook context"])
  end

  it "keeps the full context hook on SessionStart" do
    config = configurator.send(:build_hooks_config, "INGEST", "SWEEP", "NUDGE")
    session_start = config["hooks"]["SessionStart"].first["hooks"].map { |h| h["command"] }

    expect(session_start).to eq(["claude-memory hook context"])
  end
end
