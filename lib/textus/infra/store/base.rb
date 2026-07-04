module Textus
  module Infra
    class Store
      class Base
        def initialize(database)
          @db = database
        end

        private

        def table(name)
          @db[name]
        end

        def result(row)
          row&.transform_keys(&:to_sym)
        end

        def results(rows)
          rows.map { |r| result(r) }
        end
      end
    end
  end
end
