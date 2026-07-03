module Textus
  module Infra
    class Store
      module Index
        class Lookup
          def initialize(store:)
            @db = store.db
          end

          def find_by_hash(hash)
            row = @db[:entries].where(Sequel.lit("json_extract(content, '$.content_hash') = ?", hash)).first
            row&.dig(:key)
          end

          def find_by_url(url)
            row = @db[:entries].where(Sequel.lit("json_extract(content, '$.source.url') = ?", url)).first
            row&.dig(:key)
          end
        end
      end
    end
  end
end
