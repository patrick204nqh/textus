module Textus
  module Application
    module Refresh
      module All
        module_function

        def call(ctx, prefix: nil, zone: nil)
          envelope_io = Textus::Application::Writes::EnvelopeIO.new(
            file_store: ctx.file_store,
            manifest: ctx.manifest,
            schemas: ctx.schemas,
            audit_log: ctx.audit_log,
            ctx: ctx,
          )
          worker = Textus::Application::Refresh::Worker.new(ctx: ctx, envelope_io: envelope_io)

          stale_rows = Textus::Application::Reads::Stale.new(ctx: ctx).call(prefix: prefix, zone: zone)
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
