module Textus
  module Lanes
    module Scratchpad
      module Handlers
        module_function

        SESSION_PARENT_KEY = "scratchpad.sessions"

        def session_open(ctx:, call:)
          uuid = SecureRandom.uuid
          key = "scratchpad.sessions.#{uuid}.session"
          mentry = parent_mentry(ctx)

          base = File.join(ctx.layout.lane_path("scratchpad"), "sessions", uuid)
          %w[scripts notes output].each { |d| FileUtils.mkdir_p(File.join(base, d)) }

          content = { "session_id" => uuid, "created_at" => Time.now.utc.iso8601, "status" => "active" }
          ctx.write(key, mentry:, payload: ctx.payload(body: JSON.generate(content)), call:)

          { "session_id" => uuid, "status" => "active", "workspace" => base }
        end

        def parent_mentry(ctx)
          ctx.manifest.data.entries.find { |e| e.key == SESSION_PARENT_KEY }
        end

        def session_close(session_id:, ctx:, call:)
          key = "scratchpad.sessions.#{session_id}.session"
          env = ctx.read(key)
          raise Textus::UsageError.new("session not found: #{session_id}") unless env

          mentry = parent_mentry(ctx)
          current = JSON.parse(env.body || "{}")
          content = current.merge("status" => "sealed", "closed_at" => Time.now.utc.iso8601)
          ctx.write(key, mentry:, payload: ctx.payload(body: JSON.generate(content)), call:)

          { "session_id" => session_id, "status" => "sealed" }
        end
      end
    end
  end
end
