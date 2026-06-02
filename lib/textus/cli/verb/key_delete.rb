module Textus
  class CLI
    class Verb
      class KeyDelete < Verb
        command_name "delete"
        parent_group Group::Key

        option :as_flag, "--as=ROLE"
        option :dry_run, "--dry-run"
        option :prefix, "--prefix"
        option :if_etag, "--if-etag=E"

        def call(store)
          if prefix
            p = positional.shift or raise UsageError.new("key delete --prefix requires <prefix>")
            emit(session_for(store).key_delete_prefix(prefix: p, dry_run: dry_run || false).to_h)
          else
            key = positional.shift or raise UsageError.new("key delete requires <key>")
            emit(session_for(store).delete(key, if_etag: if_etag))
          end
        end
      end
    end
  end
end
