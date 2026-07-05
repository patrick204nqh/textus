module Textus
  module Lanes
    module Ingest
      module EntryTypes
        module Text
          module_function

          def build(path:, time:, label: nil, **)
            { "source" => { "kind" => "file", "path" => path,
                            "label" => label || File.basename(path) },
              "ingested_at" => time.utc.iso8601, "body" => File.read(path) }
          end
        end
      end
    end
  end
end
