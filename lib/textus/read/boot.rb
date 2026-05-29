module Textus
  module Read
    # Dispatched use case for the `boot` verb. The orientation envelope is
    # built by the Textus::Boot library module; this class is the uniform
    # (container:, call:) entry point that Dispatcher::VERBS resolves to.
    # Boot is role-independent, so `call` is not consulted.
    class Boot
      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call
        Textus::Boot.build(container: @container)
      end
    end
  end
end
