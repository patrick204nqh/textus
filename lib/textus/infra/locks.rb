require "fileutils"
require "socket"
require "time"

module Textus
  module Infra
    module Locks
      class WatcherLock
        def initialize(root, file_store: Infra::FileStore.new)
          @root = File.expand_path(root)
          @file_store = file_store
          @path = File.join(@root, ".state", "ephemeral", "locks", "watcher.lock")
          @file = nil
          @file_store.mkdir_p(File.dirname(@path))
        end

        def self.running?(root, file_store: Infra::FileStore.new)
          path = File.join(root, ".state", "ephemeral", "locks", "watcher.lock")
          return false unless file_store.exists?(path)

          File.open(path, "r+") do |file|
            got = file.flock(File::LOCK_EX | File::LOCK_NB)
            file.flock(File::LOCK_UN) if got
            return !got
          end
        rescue Errno::ENOENT
          false
        end

        def acquire
          @file = File.open(@path, File::RDWR | File::CREAT, 0o644)
          raise "watcher already running" unless @file.flock(File::LOCK_EX | File::LOCK_NB)

          @file.write("pid=#{Process.pid} host=#{Socket.gethostname}\n")
          @file.flush
          self
        end

        def release
          return unless @file

          @file.flock(File::LOCK_UN)
          @file.close
          @file_store.delete(@path) if @file_store.exists?(@path)
          @file = nil
        end
      end
    end
  end
end
