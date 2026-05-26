module Textus
  class CLI
    class Verb
      class Delete < Verb
        option :as_flag, "--as=ROLE"
        option :if_etag, "--if-etag=E"

        def call(store)
          key = positional.shift or raise UsageError.new("delete requires a key")
          emit(operations_for(store).writes.delete.call(key, if_etag: if_etag))
        end
      end
    end
  end
end
