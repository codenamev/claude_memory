# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module ClaudeMemory
  module Hook
    # Mirrors Claude Code auto-memory (~/.claude/projects/<slug>/memory/*.md)
    # into extraction candidates surfaced alongside the SessionStart distillation
    # prompt. Diffs files against a per-project state file (mtime+md5) so only
    # new or changed entries are emitted. Idempotent — unchanged files are
    # skipped on re-run.
    #
    # The emission is a *hint* to Claude that auto-memory has content worth
    # mirroring into claude_memory via `memory.store_extraction`. The mirror
    # never writes facts itself; the normal extraction review flow still applies.
    class AutoMemoryMirror
      MAX_CANDIDATES = 5
      MAX_TEXT_PER_ITEM = 1500
      STATE_FILENAME = "auto_memory_mirror.json"

      # Derive auto-memory directory from a project path using Claude Code's
      # slug convention. Both path separators and underscores are converted
      # to hyphens — e.g. `/Users/me/src/my_app` →
      # `~/.claude/projects/-Users-me-src-my-app/memory`. Before the
      # underscore conversion was added (2026-05-21 audit), this method
      # silently missed auto-memory for any project name containing `_`,
      # including claude_memory itself.
      def self.default_dir(project_path, claude_config_dir)
        slug = project_path.to_s.tr("/_", "-")
        File.join(claude_config_dir, "projects", slug, "memory")
      end

      def self.default_state_file(project_path)
        File.join(project_path, ".claude", STATE_FILENAME)
      end

      def initialize(auto_memory_dir:, state_file:)
        @auto_memory_dir = auto_memory_dir
        @state_file = state_file
      end

      # @return [Array<Hash>] candidate entries — each {name:, path:, content:, signature:}
      def pending_candidates(limit: MAX_CANDIDATES)
        return [] unless Dir.exist?(@auto_memory_dir)

        state = load_state
        files = Dir.glob(File.join(@auto_memory_dir, "*.md")).sort_by { |p| -File.mtime(p).to_i }

        files.each_with_object([]) do |path, candidates|
          break candidates if candidates.size >= limit
          name = File.basename(path)
          signature = file_signature(path)
          prior = state[name]
          next if prior.is_a?(Hash) && prior["md5"] == signature[:md5]

          candidates << {
            name: name,
            path: path,
            content: Core::TextBuilder.truncate(safe_read(path), MAX_TEXT_PER_ITEM),
            signature: signature
          }
        end
      rescue => e
        ClaudeMemory.logger.warn("AutoMemoryMirror#pending_candidates failed: #{e.message}")
        []
      end

      # Record the given candidates as the new baseline so they won't be
      # re-emitted until their content changes. Call only after the candidates
      # have actually been surfaced to the user.
      def commit(candidates)
        return if candidates.empty?

        state = load_state
        candidates.each do |c|
          state[c[:name]] = {"md5" => c[:signature][:md5], "mtime" => c[:signature][:mtime]}
        end
        write_state(state)
      rescue => e
        ClaudeMemory.logger.warn("AutoMemoryMirror#commit failed: #{e.message}")
      end

      private

      def file_signature(path)
        bytes = safe_read(path)
        {
          md5: Digest::MD5.hexdigest(bytes),
          mtime: File.mtime(path).to_i
        }
      end

      def safe_read(path)
        File.read(path)
      rescue => e
        ClaudeMemory.logger.debug("AutoMemoryMirror read failed for #{path}: #{e.message}")
        ""
      end

      def load_state
        return {} unless File.exist?(@state_file)
        parsed = JSON.parse(File.read(@state_file))
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def write_state(state)
        FileUtils.mkdir_p(File.dirname(@state_file))
        File.write(@state_file, JSON.pretty_generate(state))
      end
    end
  end
end
