# frozen_string_literal: true

module Textus
  module Action
    class Doctor < Base
      extend Textus::Contract::DSL

      verb :doctor
      summary "Run health checks on the textus store and report any issues."
      surfaces :cli
      cli "doctor"
      arg :checks, Array, required: false, description: "subset of check names to run (default: all)"

      def initialize(checks: nil)
        super()
        @checks = checks
      end

      def call(container:, call:, **)
        Textus::Doctor.build(container: container, checks: @checks, role: call.role)
      end
    end
  end
end
