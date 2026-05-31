require "fileutils"

module Textus
  # Per-role cursor cache under <root>/.state/cursor.<role>. A convenience so
  # `textus pulse` (no --since) means "since I last looked". Gitignored;
  # losing it just re-emits recent deltas, never corrupts the store. ADR 0036.
  class CursorStore
    def initialize(root:, role:)
      @path = File.join(root, ".state", "cursor.#{role}")
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
