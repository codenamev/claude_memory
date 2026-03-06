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

task default: %i[spec standard]
