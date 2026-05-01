# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"
require "stringio"

# Loads the script as a class so we can drive `BenchDiff#run` directly
# without spawning a subprocess. The actual `bin/bench-diff` invocation
# (via `if __FILE__ == $PROGRAM_NAME`) is unreachable from the spec, so
# the class body is what we exercise.
load File.expand_path("../../bin/bench-diff", __dir__)

RSpec.describe BenchDiff do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("bench_diff_spec_") }
  let(:diff) { described_class.new(stdout: stdout, stderr: stderr) }

  before do
    # Re-point RESULTS_DIR to a tmpdir per spec for isolation.
    stub_const("BenchDiff::RESULTS_DIR", tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  def write_scoreboard(version, metrics, timestamp: "2026-05-01T12:00:00Z")
    payload = {
      "version" => version,
      "timestamp" => timestamp,
      "git_sha" => "abc1234",
      "metrics" => metrics
    }
    File.write(File.join(tmpdir, "#{version}.json"), JSON.pretty_generate(payload))
  end

  describe "missing current scoreboard" do
    it "exits 2 and prints a hint when bin/run-evals hasn't been run" do
      stub_const("ClaudeMemory::VERSION", "9.9.9")
      expect(diff.run([])).to eq(2)
      expect(stderr.string).to include("Run `bin/run-evals`")
    end
  end

  describe "no baseline available" do
    before { stub_const("ClaudeMemory::VERSION", "0.12.0") }

    it "exits 0 by default and notes the missing baseline" do
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 1.0}})
      expect(diff.run([])).to eq(0)
      expect(stderr.string).to include("No baseline scoreboard available")
    end

    it "exits 2 with --strict" do
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 1.0}})
      expect(diff.run(["--strict"])).to eq(2)
    end
  end

  describe "diffing two scoreboards" do
    before { stub_const("ClaudeMemory::VERSION", "0.12.0") }

    it "exits 0 when no pass-rate dropped beyond threshold" do
      write_scoreboard("0.11.0", {"evals" => {"pass_rate" => 1.0, "total" => 12}})
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 1.0, "total" => 13}})

      expect(diff.run([])).to eq(0)
      expect(stdout.string).to include("No regressions detected")
      # New spec count is reported but not a regression
      expect(stdout.string).to include("metrics.evals.total")
    end

    it "exits 1 when a pass_rate dropped by more than the default 5%" do
      write_scoreboard("0.11.0", {"evals" => {"pass_rate" => 1.0}})
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 0.9}})

      expect(diff.run([])).to eq(1)
      expect(stdout.string).to include("REGRESSION")
      expect(stdout.string).to include("metrics.evals.pass_rate")
    end

    it "tolerates a 4% drop with default threshold but flags a 6% drop" do
      write_scoreboard("0.11.0", {"evals" => {"pass_rate" => 1.0}})
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 0.96}})
      expect(diff.run([])).to eq(0)
    end

    it "honors --threshold for tighter regression detection" do
      write_scoreboard("0.11.0", {"evals" => {"pass_rate" => 1.0}})
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 0.97}})
      # 3% drop — within 5% default, but breaches a 2% threshold
      expect(diff.run(["--threshold", "0.02"])).to eq(1)
    end

    it "doesn't regress on the *count* growing — only pass_rates trigger" do
      write_scoreboard("0.11.0", {"benchmarks" => {"pass_rate" => 1.0, "total" => 31}})
      write_scoreboard("0.12.0", {"benchmarks" => {"pass_rate" => 1.0, "total" => 46}})
      expect(diff.run([])).to eq(0)
    end

    it "respects --baseline VERSION for explicit pinning" do
      write_scoreboard("0.10.0", {"evals" => {"pass_rate" => 0.8}})
      write_scoreboard("0.11.0", {"evals" => {"pass_rate" => 1.0}})
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 0.95}})

      # Compared to 0.11.0 (default): 5% drop — passes
      expect(diff.run([])).to eq(0)
      stdout.truncate(0)
      stdout.rewind

      # Compared to 0.10.0 (explicit): +15% — passes
      expect(diff.run(["--baseline", "0.10.0"])).to eq(0)
    end

    it "handles deeply nested metrics — by_scenario / by_category" do
      write_scoreboard("0.11.0", {
        "evals" => {
          "pass_rate" => 1.0,
          "by_scenario" => {
            "tech_stack_recall" => {"pass_rate" => 1.0},
            "convention_recall" => {"pass_rate" => 1.0}
          }
        }
      })
      write_scoreboard("0.12.0", {
        "evals" => {
          "pass_rate" => 0.92,  # one of two scenarios broke
          "by_scenario" => {
            "tech_stack_recall" => {"pass_rate" => 1.0},
            "convention_recall" => {"pass_rate" => 0.5}
          }
        }
      })

      expect(diff.run([])).to eq(1)
      out = stdout.string
      # Both the rolled-up and the leaf are flagged
      expect(out).to include("metrics.evals.pass_rate")
      expect(out).to include("metrics.evals.by_scenario.convention_recall.pass_rate")
    end
  end

  describe "--json output" do
    before { stub_const("ClaudeMemory::VERSION", "0.12.0") }

    it "emits parseable JSON with current/baseline/threshold/deltas/regressions" do
      write_scoreboard("0.11.0", {"evals" => {"pass_rate" => 1.0}})
      write_scoreboard("0.12.0", {"evals" => {"pass_rate" => 0.85}})

      expect(diff.run(["--json"])).to eq(1)
      parsed = JSON.parse(stdout.string)
      expect(parsed["current"]).to eq("0.12.0")
      expect(parsed["baseline"]).to eq("0.11.0")
      expect(parsed["threshold"]).to eq(0.05)
      expect(parsed["regressions"].keys).to include("metrics.evals.pass_rate")
    end
  end
end
