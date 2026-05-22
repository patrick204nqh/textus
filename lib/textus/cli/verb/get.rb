module Textus
  class CLI
    class Verb
      class Get < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("get requires a key")
          ctx = context_for(store)
          result = Textus::Composition.reads_get(ctx).call(key)
          raise Textus::UnknownKey.new(key, suggestions: store.manifest.suggestions_for(key)) if result.nil?

          emit(result)
        end
      end
    end
  end
end
