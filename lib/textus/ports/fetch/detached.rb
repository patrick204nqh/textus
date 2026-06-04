module Textus
  module Ports
    module Fetch
      module Detached
        module_function

        def supported?
          Process.respond_to?(:fork)
        end

        def acting_role(store)
          store.manifest.policy.actor_for("fetch")
        end

        def spawn(store_root:, key:)
          return nil unless supported?

          pid = Process.fork do
            $stdin.close
            $stdout.reopen(File::NULL, "w")
            $stderr.reopen(File::NULL, "w")

            lock = Textus::Ports::Fetch::Lock.new(root: store_root, key: key)
            exit(0) unless lock.try_acquire

            begin
              store = Textus::Store.new(store_root)
              # No fetch-holder configured — exit the child cleanly. In practice
              # this is unreachable: the background fork only happens after a
              # foreground fetch was already authorized (so a fetch-holder
              # exists). Config-time detection is doctor's job (ADR 0044 Q2).
              role = acting_role(store)
              exit(0) unless role
              # FetchWorker is the internal executor since the public `fetch`
              # verb was collapsed (ADR 0079); drive it directly.
              Textus::Write::FetchWorker.new(
                container: store.container, call: Textus::Call.build(role: role),
              ).run(key)
            rescue StandardError
              # Already logged via :fetch_failed; exit cleanly.
            ensure
              lock.release
              exit(0)
            end
          end
          Process.detach(pid)
          pid
        end
      end
    end
  end
end
