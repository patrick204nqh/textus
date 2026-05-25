require "json"
require "time"

module Textus
  class CLI
    class Verb
      # One-shot, 0.12.0-only. Removal scheduled for 0.13.0.
      # Rewrites legacy audit-log role names (ai→agent, script→runner, build→builder)
      # in place under flock(LOCK_EX), then appends an idempotency marker.
      # Second invocations are a no-op: the marker prevents re-processing.
      class AuditRewriteLegacyRoles < Verb
        ROLE_REMAP = { "ai" => "agent", "script" => "runner", "build" => "builder" }.freeze
        MARKER_VERB = "audit-rewrite-legacy-roles-marker".freeze

        def self.needs_store? = false

        def parse(argv)
          raise UsageError.new("audit-rewrite-legacy-roles takes no arguments") unless argv.empty?
        end

        def call(_store)
          log = File.join(resolve_root, "audit.log")
          unless File.exist?(log)
            emit({ "ok" => true, "rewrote" => 0, "marker_appended" => false, "reason" => "no audit log" })
            return
          end

          File.open(log, "r+") { |f| rewrite_under_lock(f) }
        end

        private

        def rewrite_under_lock(f)
          f.flock(File::LOCK_EX)
          lines = f.read.lines

          if already_marked?(lines)
            emit({ "ok" => true, "rewrote" => 0, "marker_appended" => false, "reason" => "marker already present" })
            return
          end

          rewrote, rewritten = remap_lines(lines)

          if rewrote.zero?
            emit({ "ok" => true, "rewrote" => 0, "marker_appended" => false })
            return
          end

          f.rewind
          f.write(rewritten.join)
          f.write(build_marker(rewrote))
          f.truncate(f.pos)
          emit({ "ok" => true, "rewrote" => rewrote, "marker_appended" => true })
        end

        def already_marked?(lines)
          lines.any? do |l|
            JSON.parse(l)["verb"] == MARKER_VERB
          rescue JSON::ParserError
            false
          end
        end

        def remap_lines(lines)
          rewrote = 0
          rewritten = lines.map do |line|
            row = JSON.parse(line)
            if (new_role = ROLE_REMAP[row["role"]])
              row["role"] = new_role
              rewrote += 1
            end
            JSON.generate(row) + "\n"
          rescue JSON::ParserError
            line
          end
          [rewrote, rewritten]
        end

        def build_marker(rewrote)
          row = {
            "ts" => Time.now.utc.iso8601,
            "role" => "builder",
            "verb" => MARKER_VERB,
            "key" => nil,
            "etag_before" => nil,
            "etag_after" => nil,
            "details" => { "rewrote" => rewrote, "remap" => ROLE_REMAP },
          }
          JSON.generate(row) + "\n"
        end

        def resolve_root
          return @cwd if File.basename(@cwd) == ".textus"

          File.join(@cwd, ".textus")
        end
      end
    end
  end
end
