module Textus
  class CLI
    class Verb
      class Build < Verb
        option :prefix, "--prefix=K"

        def call(store)
          ctx = Textus::Composition.context(store, role: "builder")
          emit(Textus::Composition.writes_build(ctx).call(prefix: prefix))
        end
      end
    end
  end
end
