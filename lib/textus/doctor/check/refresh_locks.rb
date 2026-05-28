module Textus
  module Doctor
    class Check
      # Lists per-key refresh lock files under <root>/.locks/ whose
      # recorded PID is no longer running. These are forensic artifacts only:
      # Refresh::Lock uses flock(2), which the kernel releases on process
      # death, so stale files do not block subsequent acquires. The check
      # exists to let users clean up clutter and notice unexpected accumulation
      # (e.g. a refresh path that crashes repeatedly).
      class RefreshLocks < Check
        def call
          dir = File.join(root, ".locks")
          return [] unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.lock")).filter_map { |path| inspect_lock(path) }
        end

        private

        def inspect_lock(path)
          pid = File.read(path).strip.to_i
          return nil if pid.zero?
          return nil if pid_alive?(pid)

          {
            "code" => "refresh_lock.stale",
            "level" => "info",
            "subject" => path,
            "message" => "refresh lock file at #{path} records dead PID #{pid} " \
                         "(does not block refresh; flock is kernel-released on exit)",
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
