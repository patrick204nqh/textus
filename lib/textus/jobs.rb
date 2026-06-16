module Textus
  module Jobs
    @registry = {}

    def self.registry = @registry

    def self.register(klass)
      @registry[klass::TYPE] = klass if klass.const_defined?(:TYPE, false)
    end

    def self.fetch(type)
      @registry.fetch(type) { raise Textus::UsageError.new("unknown job type: #{type}") }
    end
  end
end
