module Textus
  class CLI
    class Verb
      class Build < Verb
        option :prefix, "--prefix=K"

        def call(store)
          emit(Textus::Operations.for(store, role: "builder").writes.build.call(prefix: prefix))
        end
      end
    end
  end
end
