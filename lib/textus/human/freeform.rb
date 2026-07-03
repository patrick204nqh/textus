module Textus
  module Human
    module Freeform
      def self.entries(manifest)
        manifest.data.entries.reject { |e| e.key.start_with?("knowledge.loop.") }
      end

      def self.get(store, key)
        store.get(key:)
      end
    end
  end
end
