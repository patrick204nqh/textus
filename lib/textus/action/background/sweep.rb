# frozen_string_literal: true

module Textus
  module Action
    module Background
      class Sweep < Action::Base
        extend Textus::Contract::DSL

        verb :sweep
        summary "Apply retention policy — drop expired entries from the store"
        arg :scope, Hash, default: {}, description: "scope hash with optional prefix/lane keys"
        arg :key, String, required: false, description: "single entry key to sweep"

        REQUIRED_ROLE = Textus::Role::AUTOMATION
        TYPE = "sweep"
        BURN = :async

        def initialize(scope: nil, key: nil)
          super()
          @scope = scope || {}
          @key   = key
        end

        def args = { scope: @scope, key: @key }.compact

        def call(container:, call:)
          prefix = @key || (@scope.is_a?(Hash) ? @scope["prefix"] : nil)
          lane   = @scope.is_a?(Hash) ? @scope["lane"] : nil
          rows = Textus::Core::Retention::Sweep.new(
            manifest: container.manifest,
            file_stat: Textus::Ports::Storage::FileStat.new,
            clock: Textus::Ports::Clock.new,
          ).call(prefix: prefix, lane: lane)
          Textus::Dispatch::Runtime::Retention::Apply.new(
            container: container, call: call,
          ).call(rows)
        end
      end
    end
  end
end
