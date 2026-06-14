# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class Doctor < Base
        extend Textus::Contract::DSL

        verb :doctor
        summary "Run health checks on the textus store and report any issues."
        surfaces :cli
        cli "doctor"
        arg :checks, Array, required: false, description: "subset of check names to run (default: all)"

        BURN = :sync

        def initialize(checks: nil)
          super()
          @checks = checks
        end

        def args
          { checks: @checks }.compact
        end

        def call(container:, **)
          Textus::Doctor.build(container: container, checks: @checks)
        end
      end
    end
  end
end
