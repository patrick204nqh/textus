# frozen_string_literal: true

module Textus
  module Step
    # Reacts to a lifecycle event (Catalog::PUBSUB). 0..N per event,
    # fire-and-forget, no meaningful return, timeout-isolated by the EventBus.
    # Declares its event with `on :event_name` and an optional key filter with
    # `match "glob.**"`. Replaces user pub/sub subscribers.
    class Observe < Base
      def self.kind = :observe

      def self.on(event = :__read__)
        if event == :__read__
          @event
        else
          @event = event.to_sym
        end
      end

      def self.match(glob = :__read__)
        if glob == :__read__
          @match
        else
          @match = glob
        end
      end

      class << self
        attr_reader :event
      end
    end
  end
end
