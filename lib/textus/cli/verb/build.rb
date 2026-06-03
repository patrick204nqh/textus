module Textus
  class CLI
    class Verb
      class Build < Runner::Base
        self.spec = Textus::Write::Build.contract

        option :prefix, "--prefix=K"

        def invoke(store)
          emit(store.as(resolved_role(store)).build(prefix: prefix))
        end
      end
    end
  end
end
