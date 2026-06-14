# frozen_string_literal: true

module Textus
  module Background
    module Job
      @registry = []

      def self.registry = @registry

      def self.fetch(type)
        @registry.each { |k| return k if k.const_defined?(:TYPE, false) && type == k::TYPE }
        raise Textus::UsageError.new("unknown job type: #{type}")
      end
    end
  end
end
