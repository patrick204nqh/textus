# frozen_string_literal: true

module Textus
  class Store
    class Compositor
      def initialize(container)
        @container = container
      end

      def write(key, mentry:, payload:, if_etag: nil, call:)
        Textus::Store::Envelope::Writer.from(container: @container, call: call)
          .put(key, mentry: mentry, payload: payload, if_etag: if_etag)
      end

      def read(key)
        Textus::Store::Envelope::Reader.from(container: @container).read(key)
      end

      def delete(key, mentry: nil, if_etag: nil, call:)
        Textus::Store::Envelope::Writer.from(container: @container, call: call)
          .delete(key, mentry: mentry, if_etag: if_etag)
      end

      def move(from_key:, to_key:, new_mentry:, if_etag: nil, call:)
        Textus::Store::Envelope::Writer.from(container: @container, call: call)
          .move(from_key: from_key, to_key: to_key, new_mentry: new_mentry, if_etag: if_etag)
      end

      def exists?(key)
        Textus::Store::Envelope::Reader.from(container: @container).exists?(key)
      end
    end
  end
end
