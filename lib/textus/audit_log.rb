require "time"

module Textus
  class AuditLog
    def initialize(root)
      @path = File.join(root, "audit.log")
    end

    def append(role:, verb:, key:, etag_before:, etag_after:)
      line = [
        Time.now.utc.iso8601,
        role, verb, key,
        etag_before || "NULL",
        etag_after  || "NULL",
      ].join("\t") + "\n"
      File.open(@path, File::WRONLY | File::APPEND | File::CREAT, 0o644) do |f|
        f.flock(File::LOCK_EX)
        f.write(line)
      end
    end
  end
end
