$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "textus"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |c|
  c.expect_with(:rspec) { |e| e.syntax = :expect }
  c.disable_monkey_patching!
  c.order = :random
  Kernel.srand c.seed
end
