# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Sets up git-lfs tracking for the project memory database.
    # This allows committing .claude/memory.sqlite3 to a git repository
    # without bloating the repo, using Git Large File Storage.
    class GitLfsCommand < BaseCommand
      TRACKED_PATTERN = ".claude/memory.sqlite3"

      def call(args)
        opts = parse_options(args, {compact: true}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory git-lfs [options]"
            parser.on("--no-compact", "Skip compacting before setup") { o[:compact] = false }
          end
        end
        return 1 if opts.nil?

        return failure("Not a git repository. Run this from a project root.") unless git_repo?
        return failure("git-lfs is not installed. Install it first: https://git-lfs.com") unless git_lfs_installed?

        if already_tracked?
          stdout.puts "git-lfs is already tracking #{TRACKED_PATTERN}"
          return 0
        end

        if opts[:compact]
          stdout.puts "Compacting project database before setup..."
          compact_project_db
        end

        setup_git_lfs
        0
      end

      private

      def git_repo?
        system("git", "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
      end

      def git_lfs_installed?
        system("git", "lfs", "version", out: File::NULL, err: File::NULL)
      end

      def already_tracked?
        return false unless File.exist?(".gitattributes")

        File.read(".gitattributes").include?(TRACKED_PATTERN)
      end

      def compact_project_db
        db_path = ClaudeMemory::Store::StoreManager.new.project_db_path
        if File.exist?(db_path)
          CompactCommand.new(stdout: stdout, stderr: stderr).call(["--scope", "project"])
        else
          stdout.puts "No project database found, skipping compact."
        end
      end

      def setup_git_lfs
        # Initialize git-lfs in the repo
        run_cmd("git", "lfs", "install", "--local")

        # Track the sqlite3 file (adds to .gitattributes)
        run_cmd("git", "lfs", "track", TRACKED_PATTERN)

        # Also track WAL/SHM files in case they exist at commit time
        run_cmd("git", "lfs", "track", "#{TRACKED_PATTERN}-shm")
        run_cmd("git", "lfs", "track", "#{TRACKED_PATTERN}-wal")

        # Update .gitignore: remove the project memory.sqlite3 entries
        update_gitignore

        stdout.puts ""
        stdout.puts "git-lfs setup complete!"
        stdout.puts ""
        stdout.puts "Files tracked via LFS:"
        stdout.puts "  #{TRACKED_PATTERN}"
        stdout.puts "  #{TRACKED_PATTERN}-shm"
        stdout.puts "  #{TRACKED_PATTERN}-wal"
        stdout.puts ""
        stdout.puts "Next steps:"
        stdout.puts "  1. git add .gitattributes .gitignore"
        stdout.puts "  2. git add .claude/memory.sqlite3"
        stdout.puts "  3. git commit -m 'Add project memory via git-lfs'"
      end

      def update_gitignore
        gitignore_path = ".gitignore"
        return unless File.exist?(gitignore_path)

        lines = File.readlines(gitignore_path)
        # Remove lines that ignore the project memory sqlite3 files
        patterns_to_remove = [
          ".claude/memory.sqlite3\n",
          ".claude/memory.sqlite3-shm\n",
          ".claude/memory.sqlite3-wal\n"
        ]

        new_lines = lines.reject { |line| patterns_to_remove.include?(line) }

        if new_lines.length < lines.length
          File.write(gitignore_path, new_lines.join)
          stdout.puts "Updated .gitignore: removed project memory exclusions"
        end
      end

      def run_cmd(*cmd)
        unless system(*cmd, out: File::NULL, err: File::NULL)
          stderr.puts "Command failed: #{cmd.join(" ")}"
        end
      end
    end
  end
end
