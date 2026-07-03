module Textus
  module Lanes
    module Ingest
      module EntryTypes
        module Text
          module_function
  
          def build(path:, label: nil, **)
            { "source" => { "kind" => "file", "path" => path,
                            "label" => label || File.basename(path) },
              "body" => File.read(path) }
          end
        end
      end
    end
  end
end
  