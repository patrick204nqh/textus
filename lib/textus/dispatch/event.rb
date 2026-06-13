# frozen_string_literal: true

module Textus
  module Dispatch
    # Thin signal: what fired, who fired it, what should run in response.
    # `actions` is an Array of Action instances declared at the fire site.
    # `correlation_id` threads one logical request through cascaded events.
    Event = Data.define(:name, :actor, :target, :payload, :actions, :correlation_id)
  end
end
