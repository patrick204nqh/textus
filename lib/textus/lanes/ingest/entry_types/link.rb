module Textus
  module Lanes
    module Ingest
      module EntryTypes
        module Link
          module_function
  
          def build(url:, label: nil, **)
            { "source" => { "kind" => "url", "url" => url, "label" => label || url },
              "body" => nil }
          end
        end
      end
    end
  end
end
  