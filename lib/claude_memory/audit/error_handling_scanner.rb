# frozen_string_literal: true

require "prism"

module ClaudeMemory
  module Audit
    # Pure-static scanner for error-handling anti-patterns in Ruby source.
    #
    # Codifies the project convention "swallowed errors stay visible": a
    # rescue that discards an exception with no value, no log, and no
    # re-raise is a silent failure the next maintainer pays for. The
    # scanner is AST-based (Prism, stdlib since Ruby 3.4) rather than
    # regex, so "empty rescue body" and "rescues Exception" are structural
    # facts, not pattern guesses.
    #
    # Functional core: #scan takes a source string and a path, returns an
    # Array<Offense>, and performs no I/O. The rake task audit:error_handling
    # is the imperative shell that reads files and prints results.
    #
    # Escape hatch: an inline comment `# [ANTI-PATTERN IGNORED]: <reason>`
    # on, within, or directly above a rescue marks a deliberate swallow.
    # Overridden offenses are still reported but never block, turning
    # silent swallows into documented ones.
    class ErrorHandlingScanner
      OVERRIDE_PATTERN = /\[ANTI-PATTERN IGNORED\]:\s*(.+)/i

      # Message-string matchers that indicate brittle control flow keyed on
      # an exception's human-readable text (`e.message.include?("locked")`).
      STRING_MATCHERS = %i[include? match match? =~ start_with? end_with? index].freeze

      # A single anti-pattern occurrence. Immutable; blocking? drives the
      # rake task exit code. An offense carrying an override_reason is a
      # documented deliberate swallow and never blocks.
      Offense = Data.define(:path, :line, :pattern, :severity, :message, :override_reason) do
        def overridden? = !override_reason.nil?

        def blocking? = severity == :error && !overridden?

        def to_h
          {path: path, line: line, pattern: pattern, severity: severity,
           message: message, override_reason: override_reason}
        end
      end

      def scan(source, path:)
        result = Prism.parse(source)
        return [] unless result.success?

        overrides = override_lines(result.comments)
        offenses = []
        walk(result.value, nil) { |node, enclosing_end| offenses.concat(inspect_node(node, path, overrides, enclosing_end)) }
        offenses
      rescue => e
        # A scanner that crashes on one pathological file must not take the
        # whole gate down. Surface the failure as an offense (visible, not
        # swallowed) and let the rest of the run continue.
        [Offense.new(path: path, line: 0, pattern: "SCANNER_ERROR", severity: :warn,
          message: "could not scan (#{e.class}: #{e.message})", override_reason: nil)]
      end

      private

      # Preorder walk that also carries the line of the nearest enclosing
      # rescuable terminator (`end`). An empty RescueNode's own location
      # stops at the `rescue` keyword, so an override comment written on a
      # blank rescue body would otherwise fall outside its span — the
      # enclosing end lets us extend the override region to the clause body.
      def walk(node, enclosing_end, &block)
        return unless node.is_a?(Prism::Node)
        yield node, enclosing_end
        child_enclosing = rescuable?(node) ? node.location.end_line : enclosing_end
        node.compact_child_nodes.each { |child| walk(child, child_enclosing, &block) }
      end

      def rescuable?(node)
        node.is_a?(Prism::BeginNode) || node.is_a?(Prism::DefNode) ||
          node.is_a?(Prism::BlockNode) || node.is_a?(Prism::LambdaNode)
      end

      def inspect_node(node, path, overrides, enclosing_end)
        case node
        when Prism::RescueNode then rescue_offenses(node, path, overrides, enclosing_end)
        when Prism::RescueModifierNode then modifier_offenses(node, path, overrides)
        else []
        end
      end

      def rescue_offenses(node, path, overrides, enclosing_end)
        line = node.location.start_line
        reason = override_for(line, rescue_end_line(node, enclosing_end), overrides)
        offenses = []

        if rescues_exception?(node)
          offenses << build(path, line, "RESCUE_EXCEPTION", :warn,
            "rescues Exception — too broad; also catches signals and system errors. Rescue StandardError or a specific class.", reason)
        end

        # Empty/nil swallows are only an anti-pattern when the rescue is
        # broad (bare, StandardError, or Exception). A narrow typed rescue
        # returning nil — `rescue JSON::ParserError; nil` — is a documented
        # "unparseable/unavailable → nil" contract, not a silent swallow,
        # so it is intentionally left unflagged.
        if broad?(node) && empty_body?(node)
          offenses << build(path, line, "EMPTY_RESCUE", :error,
            "empty body on a broad rescue — every StandardError is swallowed with no value, log, or re-raise.", reason)
        elsif broad?(node) && nil_only_body?(node)
          offenses << build(path, line, "RESCUE_NIL", :error,
            "a broad rescue returns nil and nothing else — every StandardError is silently discarded.", reason)
        elsif string_match?(node.statements)
          offenses << build(path, line, "ERROR_STRING_MATCH", :info,
            "control flow branches on the exception message text — brittle across library and Ruby versions.", reason)
        end

        offenses
      end

      def modifier_offenses(node, path, overrides)
        return [] unless node.rescue_expression.is_a?(Prism::NilNode)
        line = node.location.start_line
        [build(path, line, "RESCUE_NIL", :error,
          "`... rescue nil` swallows every StandardError into nil — the failure is invisible.",
          override_for(line, node.location.end_line, overrides))]
      end

      def empty_body?(node)
        node.statements.nil? || node.statements.body.empty?
      end

      def nil_only_body?(node)
        body = node.statements&.body
        body && body.length == 1 && body.first.is_a?(Prism::NilNode)
      end

      def rescues_exception?(node)
        node.exceptions.any? { |ex| constant_named?(ex, :Exception) }
      end

      # A rescue is broad when it catches the whole StandardError hierarchy:
      # a bare `rescue` (implicit StandardError), or an explicit StandardError
      # or Exception. Anything narrower names a specific error class and is
      # treated as a deliberate, type-scoped decision.
      def broad?(node)
        return true if node.exceptions.empty?
        node.exceptions.any? { |ex| constant_named?(ex, :StandardError) || constant_named?(ex, :Exception) }
      end

      def constant_named?(node, name)
        node.is_a?(Prism::ConstantReadNode) && node.name == name
      end

      def string_match?(statements)
        return false unless statements
        found = false
        walk(statements, nil) do |n, _|
          next if found
          next unless n.is_a?(Prism::CallNode) && STRING_MATCHERS.include?(n.name)
          receiver = n.receiver
          found = true if receiver.is_a?(Prism::CallNode) && receiver.name == :message
        end
        found
      end

      # The last line an override comment can occupy to still attach to this
      # rescue. A non-empty body ends at its own last statement; an empty
      # body borrows the enclosing terminator (the clause's `end`) so a
      # marker on the otherwise-blank body is still recognized.
      def rescue_end_line(node, enclosing_end)
        return node.location.end_line if node.statements
        enclosing_end ? enclosing_end - 1 : node.location.end_line
      end

      # An override applies when the marker comment sits on, inside, or
      # directly above the rescue clause.
      def override_for(start_line, end_line, overrides)
        span = (start_line - 1)..end_line
        overrides.each { |ln, reason| return reason if span.cover?(ln) }
        nil
      end

      def override_lines(comments)
        comments.each_with_object({}) do |comment, acc|
          match = comment.slice.match(OVERRIDE_PATTERN)
          acc[comment.location.start_line] = match[1].strip if match
        end
      end

      def build(path, line, pattern, severity, message, reason)
        Offense.new(path: path, line: line, pattern: pattern, severity: severity,
          message: message, override_reason: reason)
      end
    end
  end
end
