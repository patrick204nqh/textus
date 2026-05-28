module Textus
  class CLI
    class Verb
      class Delete < Verb
        command_name "delete"

        option :as_flag, "--as=ROLE"
        option :if_etag, "--if-etag=E"

        def call(store)
          key = positional.shift or raise UsageError.new("delete requires a key")
          emit(session_for(store).delete(key, if_etag: if_etag))
        end
      end
    end
  end
end
