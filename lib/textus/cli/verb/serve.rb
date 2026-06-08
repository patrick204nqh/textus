module Textus
  class CLI
    class Verb
      # Launches the convergence daemon in the current process. Blocks forever;
      # reclaims crashed leases and drains the queue each tick (Phase 3 adds
      # scheduled TTL re-pull/sweep). CLI-only — agents enqueue work, they do not
      # run daemons. Acts as the automation role (the build authority).
      class Serve < Verb
        command_name "serve"

        def call(store)
          call = Textus::Call.build(role: Textus::Role::AUTOMATION)
          Textus::Maintenance::Serve.new(container: store.container, call: call).run
          0
        end
      end
    end
  end
end
