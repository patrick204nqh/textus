module Textus
  module Surface
    class CLI
      class Verb
        class Get < Runner::Base
          self.spec = Textus::Protocol::VerbRegistry.for(:get)
          option :as_flag, "--as=ROLE"

          def invoke(store)
            key = positional.shift or raise UsageError.new("get requires a key")
            s = store.with_role(resolved_role(store))
            emit(s.get(key: key))
          end
        end
      end
    end
  end
end
