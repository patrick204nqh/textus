# frozen_string_literal: true

module Textus
  module Action
    @registry = {}

    # Background actions register under TYPE constants; these cannot be read
    # during Ruby's `inherited` hook (fired before class-body constants are set),
    # so we maintain an explicit map. Keep in sync with Background::* classes.
    JOB_TYPE_MAP = {
      "materialize" => "textus/action/background/materialize",
      "refresh" => "textus/action/background/refresh",
      "sweep" => "textus/action/background/sweep",
      "observe" => "textus/action/observe",
    }.freeze

    def self.registry = @registry

    def self.register(klass)
      @registry[klass.name.gsub("::", "/").downcase] = klass
    end

    def self.fetch(type)
      cached = @registry[type]
      return cached if cached

      full_path = JOB_TYPE_MAP[type]
      if full_path && @registry[full_path]
        @registry[type] = @registry[full_path]
        return @registry[type]
      end

      match = @registry.values.find { |k| k.const_defined?(:TYPE, false) && type == k::TYPE }
      if match
        @registry[type] = match
        return match
      end

      raise Textus::UsageError.new("unknown action type: #{type}")
    end

    class Base
      def self.inherited(subclass)
        super
        Textus::Action.register(subclass) if subclass.name
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
