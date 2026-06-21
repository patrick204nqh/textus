# frozen_string_literal: true

module Textus
  module Action
    class Doctor < Base

      verb :doctor
      summary "Run health checks on the textus store and report any issues."
      surfaces :cli
      cli "doctor"
      arg :checks, Array, required: false, description: "subset of check names to run (default: all)"

      def self.call(container:, call:, checks: nil, **)
        Textus::Doctor.build(container: container, checks: checks, role: call.role)
      end
    end
  end
end
