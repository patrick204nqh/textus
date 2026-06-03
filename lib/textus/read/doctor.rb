module Textus
  module Read
    # Dispatched use case for the `doctor` verb. The health-check report is
    # built by the Textus::Doctor library module; this class is the uniform
    # (container:, call:) entry point that Dispatcher::VERBS resolves to.
    # The acting role is irrelevant to a read-only health check, so `call`
    # is not consulted.
    class Doctor
      extend Textus::Contract::DSL

      verb     :doctor
      summary  "Run health checks on the textus store and report any issues."
      surfaces :cli, :ruby
      cli      "doctor"
      arg :checks, Array, required: false, description: "subset of check names to run (default: all)"

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(checks: nil)
        Textus::Doctor.build(container: @container, checks: checks)
      end
    end
  end
end
