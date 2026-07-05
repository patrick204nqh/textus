module Textus
  module Lanes
    module Ingest
      module EntryTypes
        module Link
          module_function

          def build(url:, time:, label: nil, **)
            { "source" => { "kind" => "url", "url" => url, "label" => label || url },
              "ingested_at" => time.utc.iso8601, "body" => nil }
          end
        end
      end
    end
  end
end
