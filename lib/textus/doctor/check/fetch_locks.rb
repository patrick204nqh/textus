module Textus
  module Doctor
    class Check
      # Lists per-key fetch lock files under <root>/.run/locks/ whose
      # recorded PID is no longer running. These are forensic artifacts only:
      # Fetch::Lock uses flock(2), which the kernel releases on process
      # death, so stale files do not block subsequent acquires. The check
      # exists to let users clean up clutter and notice unexpected accumulation
      # (e.g. a fetch path that crashes repeatedly).
      class FetchLocks < Check
        def call
          dir = Textus::Layout.locks(root)
          return [] unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.lock")).filter_map { |path| inspect_lock(path) }
        end

        private

        def inspect_lock(path)
          pid = File.read(path).strip.to_i
          return nil if pid.zero?
          return nil if pid_alive?(pid)

          {
            "code" => "fetch_lock.stale",
            "level" => "info",
            "subject" => path,
            "message" => "fetch lock file at #{path} records dead PID #{pid} " \
                         "(does not block fetch; flock is kernel-released on exit)",
            "fix" => "safe to delete: rm #{path}",
          }
        rescue Errno::ENOENT
          nil
        end

        def pid_alive?(pid)
          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          # Process exists but owned by another user — treat as alive.
          true
        end
      end
    end
  end
end
