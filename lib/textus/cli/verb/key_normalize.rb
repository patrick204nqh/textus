module Textus
  class CLI
    class Verb
      class KeyNormalize < Verb
        command_name "normalize"
        parent_group Group::Key

        option :write, "--write"
        option :dry_run, "--dry-run"

        def call(store)
          effective_write = write && !dry_run
          res = Textus::MigrateKeys.run(store, write: effective_write || false)
          emit(res, exit_code: res["ok"] ? 0 : 1)
        end
      end
    end
  end
end
