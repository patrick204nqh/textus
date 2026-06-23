# frozen_string_literal: true

module Textus
  module Dispatch
    # A simple registry mapping contract classes to handler factory callables.
    # The registry exposes Hash-like accessors so it can be passed around and
    # interrogated by other composition code.
    class HandlerFactoryRegistry
      def initialize
        @map = {}
      end

      def register(contract_class, factory)
        @map[contract_class] = factory
      end

      def each(&blk)
        @map.each(&blk)
      end

      def [](contract_class)
        @map[contract_class]
      end
    end
  end
end
