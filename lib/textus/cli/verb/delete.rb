module Textus
  class CLI
    class Verb
      class Delete < Verb
        option :as_flag, "--as=ROLE"
        option :if_etag, "--if-etag=E"

        def call(store)
          key = positional.shift or raise UsageError.new("delete requires a key")
          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          emit(Textus::Composition.writes_delete(ctx).call(key, if_etag: if_etag))
        end
      end
    end
  end
end
