module Textus
  module Ingest
    module IndexRebuilder
      module_function

      def rebuild!(event_store, resolver)
        Textus::Infra::Store::Index::Builder.new(store: event_store).rebuild!(resolver:)
      end
    end
  end
end
