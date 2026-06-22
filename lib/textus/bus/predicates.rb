module Textus
  module Bus
    module Predicates
      @mapping = {}

      def self.for(command_class)
        @mapping[command_class] || []
      end

      def self.register(command_class, predicate)
        @mapping[command_class] ||= []
        @mapping[command_class] << predicate
      end
    end
  end
end
