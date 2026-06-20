module Textus
  module Port
    # The wall clock. An instantiable class (ADR 0109) — uniform with the other
    # ports; `now` reads the system time. Callers that need a fixed time still
    # pass it as data via `Call#now`.
    class Clock
      def now = Time.now
    end
  end
end
