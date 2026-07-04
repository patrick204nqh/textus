module Textus
  module Lanes
    module Ingest
      module IndexRebuilder
        module_function

        def rebuild!(db, resolver)
          Textus::Infra::Store::Index::Builder.new(db).rebuild!(resolver:)
        end
      end
    end
  end
end
