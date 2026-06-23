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

  it "does not emit observations from bare always/never in code or instructions" do
    noisy = [
      "never answer from memory; OR the task is LLM-shaped with provider unstated",
      "returns a usable template, never nil. def template_for(locale) row = @db.get",
      "always returns a collection so callers don't type-check"
    ].join("\n")
    expect(distiller.distill(noisy).observations).to be_empty
  end

  it "still observes explicitly-framed conventions" do
    obs = distiller.distill("Convention: always run rubocop before every commit.").observations
    pref = obs.find { |o| o[:kind] == "preference" }
    expect(pref).not_to be_nil
    expect(pref[:body]).to match(/run rubocop/)
  end

  it "observes first-person 'we always/never' conventions" do
    obs = distiller.distill("We always run the linter before pushing to main.").observations
    expect(obs.map { |o| o[:body] }).to include(a_string_matching(/run the linter/))
  end

  it "caps a greedy decision capture to its first sentence" do
    text = "We decided to use Postgres. Then we wrote a long migration with lots of unrelated detail that should not be swallowed into the observation body at all."
    decision = distiller.distill(text).observations.find { |o| o[:kind] == "decision" }
    expect(decision[:body]).to eq("decided to use Postgres.")
  end

  it "skips bodies that are code/JSON noise" do
    expect(distiller.distill('We always {"cmd":"ls","description":"list"}').observations).to be_empty
  end

  it "dedups identical observations and caps the count" do
    obs = distiller.distill("We decided to ship. We decided to ship.").observations
    bodies = obs.map { |o| [o[:kind], o[:body]] }
    expect(bodies).to eq(bodies.uniq)
    expect(obs.size).to be <= 10
  end

  # 2026-06-23 audit (improvements #74): the high-recall Layer-1 observer was
  # scraping code/docs/transcript fragments past noise_body? and injecting them
  # into SessionStart. These pin the high-precision behavior.
  describe "high-precision noise rejection (#74)" do
    it "rejects a spec-fixture line captured after a decision phrase" do
      noisy = 'We decided to use SQLite", kind: "decision", priority: 1) expect(id).to be_a'
      expect(distiller.distill(noisy).observations).to be_empty
    end

    it "rejects a doc/CHANGELOG table-row capture (spaced pipes)" do
      noisy = "We decided to gate promotion on corroboration | Changes | Explicitly"
      expect(distiller.distill(noisy).observations).to be_empty
    end

    it "rejects benchmark tree/vector output captures" do
      noisy = "We decided to use the (vector) 78 ├─ frozen_string_literal approach"
      expect(distiller.distill(noisy).observations).to be_empty
    end

    it "rejects a method-call capture" do
      expect(distiller.distill("We decided to call insert_observation(body: x)").observations).to be_empty
    end

    it "rejects a fragment that does not begin as a prose sentence" do
      # a convention capture that starts with table/markup junk (leading pipe)
      expect(distiller.distill("Convention: | malformed table cell |").observations).to be_empty
    end

    it "still keeps a clean prose decision with a reason" do
      obs = distiller.distill("We decided to use SQLite because it is embedded.").observations
      expect(obs.map { |o| o[:body] }).to include(a_string_matching(/use SQLite because it is embedded/))
    end

    it "still keeps a clean prose convention" do
      obs = distiller.distill("Convention: prefer small focused pull requests.").observations
      expect(obs.map { |o| o[:body] }).to include(a_string_matching(/small focused pull requests/))
    end
  end
end
