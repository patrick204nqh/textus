module Textus
  module Hooks
    module Dsl
      EVENTS = %i[
        intake reduce check
        put deleted refreshed built published accepted
        mv reject loaded
        refresh_started refresh_failed refresh_detached
      ].freeze

      EVENTS.each do |event|
        define_method(event) do |name, **opts, &blk|
          Loader.current_registry.register(event, name, **opts, &blk)
        end
      end
    end
  end
end
