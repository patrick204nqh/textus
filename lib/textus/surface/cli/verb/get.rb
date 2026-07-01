module Textus
  module Surface
    class CLI
      class Verb
        class Get < Runner::Base
          self.spec = Textus::VerbRegistry.for(:get)
          option :as_flag, "--as=ROLE"

          def invoke(store)
            key = positional.shift or raise UsageError.new("get requires a key")
            spec = Textus::VerbRegistry.for(:get)
            s = store.with_role(resolved_role(store))
            result = s.entry(:get, key: key)
            result = spec.view(:cli).call(result, { key: key }) if spec.view(:cli)
            raise Textus::UnknownKey.new(key, suggestions: store.manifest.resolver.suggestions_for(key)) if result.nil?

            emit(result)
          end
        end
      end
    end
  end
end
