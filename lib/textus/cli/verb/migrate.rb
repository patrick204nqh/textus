module Textus
  class CLI
    class Verb
      class Migrate < Verb
        command_name "migrate"

        option :as_flag, "--as=ROLE"
        option :dry_run, "--dry-run"

        def call(store)
          path = positional.shift or raise UsageError.new("migrate requires <plan.yaml>")
          plan_yaml = File.read(path)
          emit(operations_for(store).migrate(plan_yaml: plan_yaml, dry_run: dry_run || false).to_h)
        end
      end
    end
  end
end
