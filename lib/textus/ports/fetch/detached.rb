module Textus
  module Ports
    module Fetch
      module Detached
        module_function

        def supported?
          Process.respond_to?(:fork)
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
              store.as("automation").fetch(key)
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
