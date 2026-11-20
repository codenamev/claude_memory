# frozen_string_literal: true

require "claude_memory"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Use NullLogger during tests to suppress log noise
  config.before(:suite) do
    ClaudeMemory.logger = ClaudeMemory::Logging::NullLogger.new

    # Hermetic embedding config: a developer's CLAUDE_MEMORY_EMBEDDING_* env
    # (e.g. fastembed set by `setup-vectors` into .claude/settings.json, which
    # Claude Code injects into every subprocess) must not leak into the suite
    # and flip provider-dependent tests. Clear it so the suite runs against the
    # tfidf default unless a test sets it explicitly.
    %w[
      CLAUDE_MEMORY_EMBEDDING_PROVIDER
      CLAUDE_MEMORY_EMBEDDING_MODEL
      CLAUDE_MEMORY_EMBEDDING_API_URL
      CLAUDE_MEMORY_EMBEDDING_API_KEY
    ].each { |var| ENV.delete(var) }
  end

  # Several specs point HOME at a tmpdir and then ENV.delete("HOME") instead of
  # restoring it. With HOME unset, Dir.home falls back to the login name, which
  # under launchd/cron resolves to /var/root, so later specs that write under
  # Dir.home fail with EACCES depending on run order. Restore HOME after every
  # example, whatever the example did to it.
  config.around do |example|
    original_home = ENV["HOME"]
    example.run
  ensure
    ENV["HOME"] = original_home
  end

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
