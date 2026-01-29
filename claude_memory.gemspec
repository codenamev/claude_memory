# frozen_string_literal: true

require_relative "lib/claude_memory/version"

Gem::Specification.new do |spec|
  spec.name = "claude_memory"
  spec.version = ClaudeMemory::VERSION
  spec.authors = ["Valentino Stoll"]
  spec.email = ["v@codenamev.com"]

  spec.summary = "Long-term, self-managed memory for Claude Code"
  spec.description = "Turn-key Ruby gem providing Claude Code with instant, high-quality, " \
                     "long-term, self-managed memory using Claude Code Hooks + MCP + Output Style."
  spec.homepage = "https://github.com/codenamev/claude_memory"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sequel", "~> 5.0"
  spec.add_dependency "sqlite3", "~> 2.0"

  # Optional high-performance SQLite adapter
  # Install with: gem install extralite
  # Provides 12-14x performance boost and better concurrency (releases GVL)
  # Will automatically use if available, otherwise falls back to sqlite3
  spec.metadata["optional_dependencies"] = "extralite:~> 2.14"
end
