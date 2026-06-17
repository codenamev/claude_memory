# frozen_string_literal: true

RSpec.describe ClaudeMemory::Distill::NullDistiller, "observations (Layer-1 Observer)" do
  let(:distiller) { described_class.new }

  it "emits no observations for plain text" do
    expect(distiller.distill("Hello world").observations).to be_empty
  end

  it "emits an important (priority 1) decision observation for a decision phrase" do
    obs = distiller.distill("We decided to adopt SQLite").observations
    decision = obs.find { |o| o[:kind] == "decision" }

    expect(decision).not_to be_nil
    expect(decision[:priority]).to eq(ClaudeMemory::Domain::Observation::IMPORTANT)
    expect(decision[:body]).to match(/adopt SQLite/)
  end

  it "emits a maybe (priority 2) preference observation for a convention phrase" do
    obs = distiller.distill("Convention: always run standard before commit").observations
    pref = obs.find { |o| o[:kind] == "preference" }

    expect(pref).not_to be_nil
    expect(pref[:priority]).to eq(ClaudeMemory::Domain::Observation::MAYBE)
  end

  it "marks scope_hint global when the text carries a global signal" do
    obs = distiller.distill("In all projects we decided to use 2-space indent").observations
    expect(obs.first[:scope_hint]).to eq("global")
  end

  it "strips JSON/escaping artifacts from bodies scraped off raw JSONL" do
    jsonl = '{"role":"assistant","content":"We decided to use PostgreSQL because we need JSONB.\\nIt scales."}'
    obs = distiller.distill(jsonl).observations
    decision = obs.find { |o| o[:kind] == "decision" }

    expect(decision[:body]).to start_with("decided to use PostgreSQL")
    expect(decision[:body]).not_to include('"}')
    expect(decision[:body]).not_to include("\\n")
    expect(decision[:body]).not_to match(/["{}\\]$/)
  end

  it "trims leading injected-memory / markdown artifacts" do
    obs = distiller.distill("### Convention: always run rubocop").observations
    pref = obs.find { |o| o[:kind] == "preference" }
    expect(pref[:body]).not_to start_with("#")
    expect(pref[:body]).not_to match(/\A[\s=>*-]/)
  end

  it "dedups identical observations and caps the count" do
    obs = distiller.distill("We decided to ship. We decided to ship.").observations
    bodies = obs.map { |o| [o[:kind], o[:body]] }
    expect(bodies).to eq(bodies.uniq)
    expect(obs.size).to be <= 10
  end
end
