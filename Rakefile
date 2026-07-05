require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :codebase_memory do
  CBM_CACHE_DIR = File.join(__dir__, ".cache", "codebase-memory")

  desc "Start codebase-memory-mcp graph visualization UI at http://localhost:9749"
  task :ui do
    mkdir_p CBM_CACHE_DIR
    ENV["CBM_CACHE_DIR"] = CBM_CACHE_DIR
    exec "codebase-memory-mcp", "--ui=true", "--port=9749"
  end
end
