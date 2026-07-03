module Textus
  module Lanes
    module Scratchpad
      module Handlers
        module_function

        def session_open(ctx:, call:)
          uuid = SecureRandom.uuid
          key = "scratchpad.sessions.#{uuid}.session"
          mentry = ctx.mentry_for(key)

          base = File.join(ctx.layout.lane_path("scratchpad"), "sessions", uuid)
          %w[scripts notes output].each { |d| FileUtils.mkdir_p(File.join(base, d)) }

          content = { "session_id" => uuid, "created_at" => Time.now.utc.iso8601, "status" => "active" }
          ctx.write(key, mentry:, payload: ctx.payload(content:))

          { "session_id" => uuid, "status" => "active", "workspace" => base }
        end

        def session_close(session_id:, ctx:, call:)
          key = "scratchpad.sessions.#{session_id}.session"
          env = ctx.read(key)
          return { error: { code: "not_found", message: "session not found: #{session_id}" } } unless env

          mentry = ctx.mentry_for(key)
          content = env.content.merge("status" => "sealed", "closed_at" => Time.now.utc.iso8601)
          ctx.write(key, mentry:, payload: ctx.payload(content:))

          { "session_id" => session_id, "status" => "sealed" }
        end
      end
    end
  end
end