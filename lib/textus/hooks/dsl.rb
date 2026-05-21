module Textus
  module Hooks
    module Dsl
      EVENTS = %i[fetch reduce check put delete refresh build accept].freeze

      EVENTS.each do |event|
        define_method(event) do |name, **opts, &blk|
          Loader.current_registry.register(event, name, **opts, &blk)
        end
      end

      def define(name, &)
        registry = Loader.current_registry
        DefineBuilder.new(registry, name).instance_eval(&)
      end
    end
  end
end
