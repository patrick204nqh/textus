require "fileutils"
require "socket"
require "time"

module Textus
  module Infra
    module Locks
      class WatcherLock
        def initialize(root, file_system: Infra::FileSystem.new)
          @root = File.expand_path(root)
          @file_system = file_system
          @path = Textus::Protocol::Layout.new(@root).lock_path("watcher")
          @file = nil
          @file_system.mkdir_p(File.dirname(@path))
        end

        def self.running?(root, file_system: Infra::FileSystem.new)
          path = Textus::Protocol::Layout.new(root).lock_path("watcher")
          return false unless file_system.exists?(path)

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
          @file_system.delete(@path) if @file_system.exists?(@path)
          @file = nil
        end
      end
    end
  end
end
