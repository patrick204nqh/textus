require "fileutils"

module Textus
  # Per-role cursor cache under <root>/.state/cursors/<role>. A convenience so
  # `textus pulse` (no --since) means "since I last looked". Gitignored;
  # losing it just re-emits recent deltas, never corrupts the store. ADR 0036/0038.
  class CursorStore
    def initialize(root:, role:)
      @path = Textus::Layout.cursor(root, role)
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
