module Textus
  class CLI
    class Verb
      class Migrate < Runner::Base
        self.spec = Textus::Maintenance::Migrate.contract

        option :as_flag, "--as=ROLE"
        option :dry_run, "--dry-run"

        def invoke(store)
          path = positional.shift or raise UsageError.new("migrate requires <plan.yaml>")
          plan_yaml = File.read(path)
          emit(session_for(store).migrate(plan_yaml: plan_yaml, dry_run: dry_run || false).to_h)
        end
      end
    end
  end
end
