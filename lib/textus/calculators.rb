require "timeout"

module Textus
  module Calculators
    REGISTRY = {}

    def self.register(name, callable)
      REGISTRY[name] = callable
    end

    def self.apply(name, rows)
      callable = REGISTRY[name] or raise UsageError.new("unknown calculator: #{name}")
      Timeout.timeout(2) { callable.call(rows) }
    rescue Timeout::Error
      raise UsageError.new("calculator '#{name}' exceeded 2s timeout")
    end
  end
end
