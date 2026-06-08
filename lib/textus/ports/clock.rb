module Textus
  module Ports
    # The wall clock. A stateless module (ADR 0108) — `now` is a pure function of
    # no collaborators, so there is nothing to inject or instantiate; callers that
    # need a fixed time pass it as data via `Call#now`, not a fake Clock.
    module Clock
      module_function

      def now = Time.now
    end
  end
end
