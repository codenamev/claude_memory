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

task default: %i[spec standard]
