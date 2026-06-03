module Textus
  class CLI
    class Verb
      class Get < Verb
        command_name "get"

        option :as_flag, "--as=ROLE"
        option :no_fetch, "--no-fetch"

        def call(store)
          key = positional.shift or raise UsageError.new("get requires a key")
          kw = no_fetch.nil? ? {} : { fetch: false }
          result = session_for(store).get(key, **kw)
          raise Textus::UnknownKey.new(key, suggestions: store.manifest.resolver.suggestions_for(key)) if result.nil?

          emit(result.to_h_for_wire)
        end
      end
    end
  end
end
