module Textus
  class CLI
    class Delete < Verb
      option :as_flag, "--as=ROLE"
      option :if_etag, "--if-etag=E"

      def call(store)
        key = positional.shift or raise UsageError.new("delete requires a key")
        role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
        emit(store.delete(key, if_etag: if_etag, as: role))
      end
    end
  end
end
