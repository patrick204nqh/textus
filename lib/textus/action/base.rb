# frozen_string_literal: true

module Textus
  module Action
    @registry = {}

    def self.registry = @registry

    def self.register(klass)
      @registry[klass.name.gsub("::", "/").downcase] = klass
    end

    def self.fetch(type)
      return @registry[type] if @registry[type]

      match = @registry.values.find { |k| k.const_defined?(:TYPE, false) && type == k::TYPE }
      raise Textus::UsageError.new("unknown action type: #{type}") unless match

      @registry[type] = match
    end

    class Base
      def self.inherited(subclass)
        super
        Textus::Action.register(subclass) if subclass.name
      end

      def call(**)
        raise NotImplementedError.new("#{self.class}#call")
      end

      def args = {}
    end
  end
end
