$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# Stdlib used pervasively across the suite. Required here once so individual
# specs don't repeat `require "tmpdir"` / "fileutils" / "json" / "yaml".
require "tmpdir"
require "fileutils"
require "json"
require "yaml"

require "textus"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |c|
  c.expect_with(:rspec) { |e| e.syntax = :expect }
  c.disable_monkey_patching!
  c.order = :random
  Kernel.srand c.seed
end
