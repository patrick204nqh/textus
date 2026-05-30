module Textus
  class CLI
    class Verb
      class Get < Verb
        command_name "get"

        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("get requires a key")
          result = session_for(store).get_or_fetch(key)
          raise Textus::UnknownKey.new(key, suggestions: store.manifest.resolver.suggestions_for(key)) if result.nil?

          emit(result.to_h_for_wire)
        end
      end
    end
  end
end
