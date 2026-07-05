require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :codebase_memory do
  desc "Start codebase-memory-mcp graph visualization UI at http://localhost:9749"
  task :ui do
    exec "codebase-memory-mcp", "--ui=true", "--port=9749"
  end
end
