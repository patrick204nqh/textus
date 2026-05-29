module Textus
  module Application
    module Write
      class RefreshAll
        def initialize(container:, call:, hook_context:)
          @container    = container
          @call         = call
          @hook_context = hook_context
        end

        def call(prefix: nil, zone: nil)
          worker = Textus::Application::Write::RefreshWorker.new(
            container: @container, call: @call, hook_context: @hook_context,
          )

          stale_rows = Textus::Application::Read::Stale::Impl.new(caps: caps_struct).call(prefix: prefix, zone: zone)
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

        private

        # Read::Stale::Impl still consumes the old caps shape.
        def caps_struct
          @caps_struct ||= Struct.new(
            :manifest, :file_store, :schemas, :root, :audit_log, :events, :authorizer
          ).new(
            @container.manifest, @container.file_store, @container.schemas, @container.root,
            @container.audit_log, @container.events, @container.authorizer
          )
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:refresh_all, Textus::Application::Write::RefreshAll, caps: :write)
