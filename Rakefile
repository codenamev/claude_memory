# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Parallel test execution for faster runs
desc "Run specs in parallel"
task :spec do
  # Use parallel_rspec if available, fall back to regular rspec
  if system("which parallel_rspec > /dev/null 2>&1")
    sh "bundle exec parallel_rspec spec/"
  else
    puts "parallel_tests not installed, running sequentially"
    sh "bundle exec rspec"
  end
end

# Sequential test execution (for debugging)
RSpec::Core::RakeTask.new(:spec_sequential)

require "standard/rake"

namespace :plugin do
  desc "Sync ClaudeMemory::VERSION into .claude-plugin/plugin.json and marketplace.json"
  task :sync_version do
    require_relative "lib/claude_memory/version"
    version = ClaudeMemory::VERSION

    %w[.claude-plugin/plugin.json .claude-plugin/marketplace.json].each do |path|
      next unless File.exist?(path)

      content = File.read(path)
      updated = content.gsub(/"version"\s*:\s*"[^"]*"/, "\"version\": \"#{version}\"")

      if content != updated
        File.write(path, updated)
        puts "Updated #{path} to version #{version}"
      else
        puts "#{path} already at version #{version}"
      end
    end
  end
end

namespace :audit do
  desc "Scan lib/ for error-handling anti-patterns (swallowed errors); exits non-zero on unignored blocking findings"
  task :error_handling do
    require_relative "lib/claude_memory/audit/error_handling_scanner"

    scanner = ClaudeMemory::Audit::ErrorHandlingScanner.new
    offenses = Dir["lib/**/*.rb"].sort.flat_map do |path|
      scanner.scan(File.read(path), path: path)
    end

    active = offenses.reject(&:overridden?)
    overridden = offenses.select(&:overridden?)
    blocking = active.select(&:blocking?)

    puts "Error-handling anti-pattern scan (lib/)"
    puts

    if active.empty?
      puts "  No active findings."
    else
      active.sort_by { |o| [o.path, o.line] }.each do |o|
        puts format("  %-45s %-18s [%s] %s", "#{o.path}:#{o.line}", o.pattern, o.severity, o.message)
      end
    end

    unless overridden.empty?
      puts
      puts "Documented swallows (overridden):"
      overridden.sort_by { |o| [o.path, o.line] }.each do |o|
        puts format("  %-45s %-18s — %s", "#{o.path}:#{o.line}", o.pattern, o.override_reason)
      end
    end

    puts
    puts format("Summary: %d blocking, %d advisory, %d overridden",
      blocking.size, active.size - blocking.size, overridden.size)

    if blocking.any?
      puts
      puts "Blocking findings must re-raise, log, return a real value, or be annotated with"
      puts "  # [ANTI-PATTERN IGNORED]: <reason>"
      abort "audit:error_handling failed with #{blocking.size} blocking finding(s)"
    end
  end
end

task default: %i[spec standard audit:error_handling]
