module Textus
  class CLI
    class Verb
      class Mv < Verb
        option :as_flag, "--as=ROLE"
        option :dry_run, "--dry-run"

        def call(store)
          old_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
          new_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
          emit(store.mv(old_key, new_key, as: resolved_role(store), dry_run: dry_run || false))
        end
      end
    end
  end
end
