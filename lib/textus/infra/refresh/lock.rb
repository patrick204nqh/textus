require "fileutils"

module Textus
  module Infra
    module Refresh
      class Lock
        def initialize(root:, key:)
          @root = root
          @key  = key
          @path = File.join(root, ".locks", "#{safe_key}.lock")
          @file = nil
        end

        def try_acquire # rubocop:disable Naming/PredicateMethod
          FileUtils.mkdir_p(File.dirname(@path))
          @file = File.open(@path, File::RDWR | File::CREAT, 0o644)
          acquired = @file.flock(File::LOCK_EX | File::LOCK_NB)
          unless acquired
            @file.close
            @file = nil
            return false
          end
          @file.write(Process.pid.to_s)
          @file.flush
          true
        end

        def release
          return unless @file

          @file.flock(File::LOCK_UN)
          @file.close
          @file = nil
        end

        private

        def safe_key
          @key.to_s.gsub(/[^a-zA-Z0-9._-]/, "_")
        end
      end
    end
  end
end
