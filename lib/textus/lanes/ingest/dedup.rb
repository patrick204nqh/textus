module Textus
  module Lanes
    module Ingest
      module Dedup
        module_function

        def find(lookup, content_hash, url: nil)
          dup = lookup.find_by_hash(content_hash)
          return dup if dup
          return nil unless url

          lookup.find_by_url(url)
        end
      end
    end
  end
end
