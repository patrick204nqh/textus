module Textus
  class CLI
    class Verb
      class Mv < Verb
        command_name "mv"
        parent_group Group::Key

        option :as_flag, "--as=ROLE"
        option :dry_run, "--dry-run"

        def call(store)
          old_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
          new_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
          emit(operations_for(store).mv(old_key, new_key, dry_run: dry_run || false))
        end
      end
    end
  end
end
