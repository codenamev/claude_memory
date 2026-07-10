# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Audit::ErrorHandlingScanner do
  subject(:scanner) { described_class.new }

  def patterns_for(source)
    scanner.scan(source, path: "lib/example.rb").map(&:pattern)
  end

  def scan(source)
    scanner.scan(source, path: "lib/example.rb")
  end

  describe "#scan" do
    it "flags a truly empty rescue body as EMPTY_RESCUE (blocking)" do
      offenses = scan(<<~RUBY)
        def a
          risky
        rescue
        end
      RUBY
      expect(offenses.map(&:pattern)).to eq(["EMPTY_RESCUE"])
      expect(offenses.first.severity).to eq(:error)
      expect(offenses.first.blocking?).to be(true)
    end

    it "flags a comment-only rescue body as EMPTY_RESCUE (a comment is not handling)" do
      expect(patterns_for(<<~RUBY)).to eq(["EMPTY_RESCUE"])
        def a
          risky
        rescue => e
          # nothing to do here
        end
      RUBY
    end

    it "flags a rescue whose only statement is nil as RESCUE_NIL" do
      expect(patterns_for(<<~RUBY)).to eq(["RESCUE_NIL"])
        def a
          risky
        rescue
          nil
        end
      RUBY
    end

    it "flags a `expr rescue nil` modifier as RESCUE_NIL" do
      expect(patterns_for("value = compute rescue nil")).to eq(["RESCUE_NIL"])
    end

    it "does NOT flag a `expr rescue fallback` modifier with a real value" do
      expect(patterns_for("n = Integer(str) rescue 0")).to be_empty
    end

    it "does NOT flag a rescue that returns a real value (predicate idiom)" do
      expect(patterns_for(<<~RUBY)).to be_empty
        def contentless?
          check
        rescue
          false
        end
      RUBY
    end

    it "does NOT flag a rescue that re-raises" do
      expect(patterns_for(<<~RUBY)).to be_empty
        def a
          risky
        rescue => e
          raise
        end
      RUBY
    end

    it "does NOT flag a narrow typed rescue returning nil (a documented fallback contract)" do
      expect(patterns_for(<<~RUBY)).to be_empty
        def parse(json)
          JSON.parse(json)
        rescue JSON::ParserError
          nil
        end
      RUBY
    end

    it "does NOT flag a narrow typed rescue with an empty (skip) body" do
      expect(patterns_for(<<~RUBY)).to be_empty
        def annotate(rows)
          decorate(rows)
        rescue Sequel::DatabaseError
          # table missing on older DBs — skip
        end
      RUBY
    end

    it "does NOT flag a narrow rescue listing several specific classes" do
      expect(patterns_for(<<~RUBY)).to be_empty
        def release
          disconnect
        rescue Sequel::DatabaseError, Errno::ENOENT
          nil
        end
      RUBY
    end

    it "DOES flag an explicit `rescue StandardError` that returns nil (broad)" do
      expect(patterns_for(<<~RUBY)).to eq(["RESCUE_NIL"])
        def a
          risky
        rescue StandardError
          nil
        end
      RUBY
    end

    it "flags `rescue Exception` as RESCUE_EXCEPTION (warn, non-blocking)" do
      offenses = scan(<<~RUBY)
        def a
          risky
        rescue Exception => e
          handle(e)
        end
      RUBY
      exception = offenses.find { |o| o.pattern == "RESCUE_EXCEPTION" }
      expect(exception).not_to be_nil
      expect(exception.severity).to eq(:warn)
      expect(exception.blocking?).to be(false)
    end

    it "flags control flow on the exception message as ERROR_STRING_MATCH (info)" do
      offenses = scan(<<~RUBY)
        def a
          risky
        rescue => e
          retry if e.message.include?("locked")
        end
      RUBY
      match = offenses.find { |o| o.pattern == "ERROR_STRING_MATCH" }
      expect(match).not_to be_nil
      expect(match.severity).to eq(:info)
      expect(match.blocking?).to be(false)
    end

    it "does not treat an ordinary .include? unrelated to a message as a match" do
      expect(patterns_for(<<~RUBY)).to be_empty
        def a
          risky
        rescue => e
          record(e) if allowed.include?(e.class)
        end
      RUBY
    end

    it "does not double-count a re-raise guarded by a message check" do
      # `raise unless e.message.include?(...)` is a message match; the body
      # is non-empty and re-raises, so only ERROR_STRING_MATCH applies.
      expect(patterns_for(<<~RUBY)).to eq(["ERROR_STRING_MATCH"])
        def a
          risky
        rescue => e
          raise unless e.message.include?("malformed")
        end
      RUBY
    end

    context "with an [ANTI-PATTERN IGNORED] override" do
      it "reports the offense but marks it overridden and non-blocking when the comment is inside the rescue" do
        offenses = scan(<<~RUBY)
          def a
            risky
          rescue
            # [ANTI-PATTERN IGNORED]: best-effort cleanup, failure is expected
          end
        RUBY
        expect(offenses.first.pattern).to eq("EMPTY_RESCUE")
        expect(offenses.first.overridden?).to be(true)
        expect(offenses.first.override_reason).to eq("best-effort cleanup, failure is expected")
        expect(offenses.first.blocking?).to be(false)
      end

      it "honors an override comment directly above the rescue keyword" do
        offenses = scan(<<~RUBY)
          def a
            risky
            # [ANTI-PATTERN IGNORED]: documented above the keyword
          rescue
            nil
          end
        RUBY
        expect(offenses.first.blocking?).to be(false)
      end
    end

    it "handles chained and nested rescues" do
      patterns = patterns_for(<<~RUBY)
        def a
          begin
            inner
          rescue
          end
        rescue Exception
        end
      RUBY
      expect(patterns).to contain_exactly("EMPTY_RESCUE", "RESCUE_EXCEPTION", "EMPTY_RESCUE")
    end

    it "returns [] for source with no rescues" do
      expect(scan("def a\n  b + c\nend")).to be_empty
    end

    it "returns [] for unparseable source rather than raising" do
      expect(scan("def broken(")).to be_empty
    end

    it "carries the supplied path and 1-indexed line on each offense" do
      offense = scanner.scan("x = risky rescue nil", path: "lib/foo.rb").first
      expect(offense.path).to eq("lib/foo.rb")
      expect(offense.line).to eq(1)
    end
  end
end
