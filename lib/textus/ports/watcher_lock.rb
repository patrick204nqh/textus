# frozen_string_literal: true

require "socket"

module Textus
  module Ports
    # Flock-based watcher presence lock. Held for the watcher's lifetime.
    # Process death releases the flock automatically.
    class WatcherLock
      def initialize(root)
        @path = StoreGeometry.new(root).lock_path("watcher")
        @file = nil
        FileUtils.mkdir_p(File.dirname(@path))
      end

      def self.running?(root)
        path = StoreGeometry.new(root).lock_path("watcher")
        return false unless File.exist?(path)

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
        FileUtils.rm_f(@path)
        @file = nil
      end
    end
  end
end
