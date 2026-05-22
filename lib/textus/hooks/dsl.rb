module Textus
  module Hooks
    module Dsl
      EVENTS = %i[fetch reduce check put delete refresh build accept publish mv reject loaded].freeze

      EVENTS.each do |event|
        define_method(event) do |name, **opts, &blk|
          Loader.current_registry.register(event, name, **opts, &blk)
        end
      end
    end
  end
end
