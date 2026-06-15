module Textus
  module Workflow
    class Registry
      def initialize
        @definitions = []
      end

      def register(definition)
        @definitions << definition
      end

      def for(key)
        @definitions.find { |d| d.match?(key) }
      end

      def all
        @definitions.dup
      end
    end
  end
end
