# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      @registry = {}

      def self.registry = @registry

      def self.register(klass)
        type = klass.name.gsub("::", "/").downcase
        @registry[type] = klass
      end

      # Base class for all actions. Subclasses declare BURN = :sync | :async.
      # call(container:, call:) performs the work and returns a result.
      # args returns a serializable Hash for Job enqueuing.
      class Base
        def self.inherited(subclass)
          super
          Textus::Dispatch::Actions.register(subclass) if subclass.name
        end

        def call(**)
          raise NotImplementedError.new("#{self.class}#call")
        end

        def args
          {}
        end
      end
    end
  end
end
