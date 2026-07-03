require "fileutils"

module Textus
  module Protocol
    class Cursor
      def initialize(root:, role:)
        @path = Textus::Protocol::Layout.new(root).cursor_path(role)
      end

      def read
        Integer(File.read(@path).strip)
      rescue Errno::ENOENT, ArgumentError
        0
      end

      def write(seq)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, seq.to_s)
        seq
      end
    end
  end
end
