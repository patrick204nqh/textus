require "fileutils"
require "socket"
require "time"

module Textus
  module Infra
    class BuildLock
      LOCK_FILENAME = ".build.lock"
      MAX_HOLDER_BYTES = 512

      def self.with(root:, &)
        new(root: root).acquire_or_raise(&)
      end

      def initialize(root:)
        @path = File.join(root, LOCK_FILENAME)
        @file = nil
      end

      def acquire_or_raise
        FileUtils.mkdir_p(File.dirname(@path))
        @file = File.open(@path, File::RDWR | File::CREAT, 0o644)
        @file.close_on_exec = true

        unless @file.flock(File::LOCK_EX | File::LOCK_NB)
          holder = read_holder_safely
          @file.close
          @file = nil
          raise Textus::BuildInProgress.new(holder)
        end

        @file.truncate(0)
        @file.write("pid=#{Process.pid} started=#{Time.now.utc.iso8601} host=#{Socket.gethostname}\n")
        @file.flush

        yield
      ensure
        release
      end

      private

      def release
        return unless @file

        @file.flock(File::LOCK_UN)
        @file.close
        @file = nil
      end

      def read_holder_safely
        content = File.read(@path, MAX_HOLDER_BYTES)
        content.gsub(/[^[:print:]\t ]/, "").strip
      rescue StandardError
        "unknown"
      end
    end
  end
end
