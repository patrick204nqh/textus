module Textus
  class CLI
    class Verb
      class ZoneMv < Runner::Base
        self.spec = Textus::Maintenance::ZoneMv.contract
        command_name "mv"
        parent_group Group::Zone

        option :as_flag, "--as=ROLE"
        option :dry_run, "--dry-run"

        def invoke(store)
          from = positional.shift or raise UsageError.new("zone mv requires <from> <to>")
          to   = positional.shift or raise UsageError.new("zone mv requires <from> <to>")
          emit(session_for(store).zone_mv(from: from, to: to, dry_run: dry_run || false).to_h)
        end
      end
    end
  end
end
