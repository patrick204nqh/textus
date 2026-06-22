module Textus
  module Dispatch
    class Pipeline
      attr_reader :container

      def initialize(registry:, container:, middleware: [])
        @registry = registry
        @middleware = middleware
        @container = container
      end

      def dispatch(command, call:)
        stack = @middleware.reverse.reduce(->(cmd, c) { execute(cmd, c) }) do |next_mw, mw|
          ->(cmd, c) { mw.call(container: @container, command: cmd, call: c, next_handler: next_mw) }
        end
        stack.call(command, call)
      end

      def write(key, mentry:, payload:, call:, if_etag: nil)
        Store::Envelope::Writer.from(container: @container, call: call)
                               .put(key, mentry: mentry, payload: payload, if_etag: if_etag)
      end

      def read(key)
        Store::Envelope::Reader.from(container: @container).read(key)
      end

      def delete(key, call:, mentry: nil, if_etag: nil)
        Store::Envelope::Writer.from(container: @container, call: call)
                               .delete(key, mentry: mentry, if_etag: if_etag)
      end

      def move(from_key:, to_key:, new_mentry:, call:, if_etag: nil)
        Store::Envelope::Writer.from(container: @container, call: call)
                               .move(from_key: from_key, to_key: to_key, new_mentry: new_mentry, if_etag: if_etag)
      end

      def exists?(key)
        Store::Envelope::Reader.from(container: @container).exists?(key)
      end

      private

      def execute(command, call)
        handler = @registry.for(command.class)
        handler.call(command, call)
      end
    end
  end
end
