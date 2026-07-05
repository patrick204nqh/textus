require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

CBM_CACHE_DIR = File.join(__dir__, ".cache", "codebase-memory")

namespace :codebase_memory do
  desc "Start codebase-memory-mcp graph visualization UI at http://localhost:9749"
  task :ui do
    mkdir_p CBM_CACHE_DIR
    ENV["CBM_CACHE_DIR"] = CBM_CACHE_DIR
    exec "codebase-memory-mcp", "--ui=true", "--port=9749"
  end
end
