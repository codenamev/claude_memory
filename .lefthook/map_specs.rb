#!/usr/bin/env ruby
# frozen_string_literal: true

# Map changed Ruby files to their corresponding spec files
# Usage: .lefthook/map_specs.rb
# Returns: Space-separated list of spec files to run

changed_files = `git diff --cached --name-only --diff-filter=ACM`.split("\n")
ruby_files = changed_files.select { |f| f.end_with?(".rb") && f.start_with?("lib/") }

# Map lib/ files to their spec/ equivalents
specs = ruby_files.map do |file|
  # lib/claude_memory/foo/bar.rb → spec/claude_memory/foo/bar_spec.rb
  file.sub("lib/", "spec/").sub(".rb", "_spec.rb")
end.select { |spec| File.exist?(spec) }

# Always run integration tests if core infrastructure changed
critical_paths = [
  "lib/claude_memory/store",
  "lib/claude_memory/mcp",
  "lib/claude_memory/hook"
]

if ruby_files.any? { |f| critical_paths.any? { |path| f.start_with?(path) } }
  specs += Dir["spec/integration/*_spec.rb"] if Dir.exist?("spec/integration")
end

# Output unique spec files
puts specs.uniq.join(" ")
