module Textus
  class CLI
    class Verb
      class Pulse < Verb
        command_name "pulse"

        option :since, "--since=N"

        def call(store)
          ops = operations_for(store)
          since_n = (since || "0").to_i
          emit(ops.pulse(since: since_n))
        end
      end
    end
  end
end
