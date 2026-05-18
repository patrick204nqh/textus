$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "textus"

RSpec.configure do |c|
  c.expect_with(:rspec) { |e| e.syntax = :expect }
  c.disable_monkey_patching!
  c.order = :random
  Kernel.srand c.seed
end
