module Textus
  class CLI
    class Verb
      class Mv < Verb
        command_name "mv"
        parent_group Group::Key

        option :as_flag, "--as=ROLE"
        option :dry_run, "--dry-run"
        option :prefix, "--prefix"

        def call(store)
          if prefix
            from_p = positional.shift or raise UsageError.new("mv --prefix requires <from-prefix> <to-prefix>")
            to_p   = positional.shift or raise UsageError.new("mv --prefix requires <from-prefix> <to-prefix>")
            emit(session_for(store).key_mv_prefix(from_prefix: from_p, to_prefix: to_p,
                                                  dry_run: dry_run || false).to_h)
          else
            old_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
            new_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
            emit(session_for(store).mv(old_key, new_key, dry_run: dry_run || false))
          end
        end
      end
    end
  end
end
