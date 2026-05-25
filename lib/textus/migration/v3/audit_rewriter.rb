require "json"
require "time"
require "fileutils"

module Textus
  module Migration
    module V3
      module AuditRewriter
        MARKER_VERB = "migration-marker"

        def self.run(root:)
          log = File.join(root, ".textus/audit.log")
          FileUtils.mkdir_p(File.dirname(log))
          FileUtils.touch(log) unless File.exist?(log)
          return if already_marked?(log)

          File.open(log, "a") do |f|
            f.flock(File::LOCK_EX)
            f.write(JSON.generate(
              "ts" => Time.now.utc.iso8601,
              "role" => "builder",
              "verb" => MARKER_VERB,
              "key" => nil,
              "etag_before" => nil,
              "etag_after" => nil,
              "details" => { "from_protocol" => "textus/2", "to_protocol" => "textus/3" },
            ) + "\n")
          end
        end

        def self.already_marked?(log)
          File.foreach(log).any? do |line|
            JSON.parse(line)["verb"] == MARKER_VERB
          rescue JSON::ParserError
            false
          end
        end
      end
    end
  end
end
