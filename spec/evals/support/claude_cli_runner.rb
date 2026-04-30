# frozen_string_literal: true

require "open3"
require "json"
require "tmpdir"

module EvalHelpers
  class ClaudeCliRunner
    MEMORY_TOOLS = %w[mcp__memory__*].freeze

    def initialize(working_dir:, memory_enabled: true, allowed_tools: nil)
      @working_dir = working_dir
      @memory_enabled = memory_enabled
      @allowed_tools = allowed_tools
    end

    # Run claude CLI with prompt and return response
    def run(prompt:, context: nil)
      full_prompt = context ? "#{context}\n\n#{prompt}" : prompt

      cmd = build_command(full_prompt)
      # Redirect stderr to null device to avoid hook errors
      output, status = Open3.capture2(*cmd, chdir: @working_dir, err: File::NULL)

      if status.success?
        parse_output(output)
      else
        {success: false, error: "CLI failed: #{output}"}
      end
    rescue => e
      {success: false, error: e.message}
    end

    private

    def build_command(prompt)
      cmd = [
        "claude",
        "-p", # Print mode (non-interactive)
        prompt,
        "--output-format", "text", # Use text format (JSON unreliable with hooks)
        "--no-session-persistence", # Don't save session
        "--max-budget-usd", "0.10" # Per-test budget limit
      ]
      if @allowed_tools&.any?
        cmd += ["--allowedTools"] + @allowed_tools
      end
      cmd
    end

    def parse_output(text_output)
      # Text output from claude -p is just the response text
      # Strip any trailing whitespace and shell reset messages
      cleaned = text_output.strip
        .split("\n")
        .reject { |line| line.start_with?("Shell cwd") }
        .join("\n")

      {
        success: true,
        result: cleaned,
        session_id: "text-mode",
        cost: estimate_cost(cleaned)
      }
    end

    def estimate_cost(text)
      # Rough estimate based on text length
      # Assume ~4 chars per token, $0.003 per 1000 input, $0.015 per 1000 output
      input_tokens = 100 # Rough estimate for prompt
      output_tokens = text.length / 4

      (input_tokens * 0.000003) + (output_tokens * 0.000015)
    end
  end

  # Factory for creating runners
  class CliRunnerFactory
    def self.baseline_runner
      tmpdir = Dir.mktmpdir("eval-baseline")
      ClaudeCliRunner.new(working_dir: tmpdir, memory_enabled: false)
    end

    def self.memory_enabled_runner(project_dir)
      ClaudeCliRunner.new(
        working_dir: project_dir,
        memory_enabled: true,
        allowed_tools: ClaudeCliRunner::MEMORY_TOOLS
      )
    end
  end
end
