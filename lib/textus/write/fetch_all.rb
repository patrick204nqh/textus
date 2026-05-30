module Textus
  module Write
    class FetchAll
      def initialize(container:, call:)
        @container    = container
        @call         = call
      end

      def call(prefix: nil, zone: nil)
        worker = Textus::Write::FetchWorker.new(
          container: @container, call: @call,
        )

        stale_rows = Textus::Read::Stale.new(container: @container, call: @call).call(prefix: prefix, zone: zone)
        fetched = []
        failed = []
        skipped = []

        stale_rows.each do |row|
          key = row["key"] || row[:key]
          reason = row["reason"] || row[:reason]
          if reason.to_s.match?(/ttl exceeded|never fetched/)
            begin
              worker.run(key)
              fetched << key
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
          "fetched" => fetched,
          "failed" => failed,
          "skipped" => skipped,
        }
      end
    end
  end
end
