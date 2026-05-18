# frozen_string_literal: true

RSpec.describe ClaudeMemory::OTel::Attributes do
  it "exposes prompt_id, session_id, and model from canonical OTel keys" do
    attrs = described_class.new(
      "prompt.id" => "p-1",
      "session.id" => "s-1",
      "gen_ai.request.model" => "claude-sonnet-4-6"
    )
    expect(attrs.prompt_id).to eq("p-1")
    expect(attrs.session_id).to eq("s-1")
    expect(attrs.model).to eq("claude-sonnet-4-6")
  end

  it "returns nil for missing keys" do
    attrs = described_class.new({})
    expect(attrs.prompt_id).to be_nil
    expect(attrs.tool_name).to be_nil
  end

  describe "#contains_prompt_content?" do
    it "is false when no prompt-content keys are present" do
      attrs = described_class.new("type" => "input", "model" => "claude-sonnet-4-6")
      expect(attrs.contains_prompt_content?).to be false
    end

    it "is true when prompt is non-empty" do
      attrs = described_class.new("prompt" => "tell me about Ruby")
      expect(attrs.contains_prompt_content?).to be true
    end

    it "is false when the prompt key is whitespace" do
      attrs = described_class.new("prompt" => "   ")
      expect(attrs.contains_prompt_content?).to be false
    end

    it "detects body, tool_input, and tool.output" do
      %w[body tool_input tool.output full_command user_prompt].each do |key|
        attrs = described_class.new(key => "x")
        expect(attrs.contains_prompt_content?).to(be(true), "expected key #{key} to flag content")
      end
    end
  end

  it "is frozen on construction" do
    expect(described_class.new({})).to be_frozen
  end
end
