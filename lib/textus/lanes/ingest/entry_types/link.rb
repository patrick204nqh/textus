module Textus
  module Lanes
    module Ingest
      module EntryTypes
        module Link
          module_function

          def build(url:, label: nil, time:, **)
            { "source" => { "kind" => "url", "url" => url, "label" => label || url },
              "ingested_at" => time.utc.iso8601, "body" => nil }
          end
        end
      end
    end
  end
end
