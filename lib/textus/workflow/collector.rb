module Textus
  module Workflow
    class Collector
      @current = nil

      class << self
        attr_reader :current
      end

      def self.with(collector)
        prev      = @current
        @current  = collector
        yield
      ensure
        @current = prev
      end

      def initialize(registry)
        @registry = registry
      end

      def register(defn)
        @registry.register(defn)
      end
    end
  end
end
