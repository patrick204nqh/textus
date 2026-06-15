module Textus
  module Workflow
    class Collector
      @current = nil

      def self.current = @current

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
