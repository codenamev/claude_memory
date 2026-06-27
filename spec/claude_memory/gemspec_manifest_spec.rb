# frozen_string_literal: true

require "rubygems"

# Guards improvement #71: the repo's tracked dogfooding DB (~96MB) must never
# ship in the published gem. It bloated the gem to ~28MB; users init their own
# DB via Configuration and never need ours.
RSpec.describe "published gem manifest" do
  let(:spec) do
    gemspec_path = File.expand_path("../../claude_memory.gemspec", __dir__)
    Gem::Specification.load(gemspec_path)
  end

  it "excludes the project memory database" do
    expect(spec.files.grep(/memory\.sqlite3/)).to be_empty
  end

  it "excludes the entire .claude/ dogfooding directory" do
    expect(spec.files.grep(%r{\A\.claude/})).to be_empty
  end

  it "still includes the plugin manifest and library code users need" do
    expect(spec.files).to include("lib/claude_memory.rb")
    expect(spec.files.grep(%r{\A\.claude-plugin/})).not_to be_empty
    expect(spec.files.grep(%r{\Acommands/})).not_to be_empty
  end
end
