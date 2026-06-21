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
      extend Contract::DSL
      extend Dry::Monads[:result]

      def self.inherited(subclass)
        super
        Textus::Action.register(subclass) if subclass.name
      end

      def self.call(**)
        raise NotImplementedError.new("#{name}.call")
      end

      def self.proposal_from(env, key:)
        proposal = env.meta&.dig("proposal") or return Failure(code: :proposal_error, message: "entry has no proposal block: #{key}")
        target = proposal["target_key"] or return Failure(code: :proposal_error, message: "proposal missing target_key")
        { proposal:, target_key: target }
      end
    end
  end
end
