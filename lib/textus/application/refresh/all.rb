module Textus
  module Application
    module Refresh
      class All
        def initialize(ctx:, caps:, rpc:, writer:, hook_context:)
          @ctx          = ctx
          @caps         = caps
          @rpc          = rpc
          @writer       = writer
          @hook_context = hook_context
        end

        def call(prefix: nil, zone: nil)
          worker = Textus::Application::Refresh::Worker.new(
            ctx: @ctx, caps: @caps, rpc: @rpc, writer: @writer,
            hook_context: @hook_context
          )

          stale_rows = Textus::Application::Reads::Stale.new(caps: @caps).call(prefix: prefix, zone: zone)
          refreshed = []
          failed = []
          skipped = []

          stale_rows.each do |row|
            key = row["key"] || row[:key]
            reason = row["reason"] || row[:reason]
            if reason.to_s.match?(/ttl exceeded|never refreshed/)
              begin
                worker.run(key)
                refreshed << key
              rescue Textus::Error => e
                failed << { "key" => key, "error" => e.message }
              end
            else
              skipped << { "key" => key, "reason" => reason }
            end
          end

          {
            "protocol" => Textus::PROTOCOL,
            "ok" => failed.empty?,
            "refreshed" => refreshed,
            "failed" => failed,
            "skipped" => skipped,
          }
        end
      end
    end
  end
end
