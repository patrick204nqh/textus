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

      def self.build_command(contract_class, inputs)
        members = contract_class.members
        kwargs = members.to_h do |member|
          [member, inputs[member]]
        end
        contract_class.new(**kwargs)
      end

      def write(key, mentry:, payload:, call:, if_etag: nil)
        writer = if container.respond_to?(:writer) && container.writer
                   container.writer.call(call)
                 else
                   Store::Envelope::Writer.from(container: @container, call: call)
                 end
        writer.put(key, mentry: mentry, payload: payload, if_etag: if_etag)
      end

      def read(key)
        reader = if container.respond_to?(:reader) && container.reader
                   container.reader
                 else
                   Store::Envelope::Reader.from(container: @container)
                 end
        reader.read(key)
      end

      def delete(key, call:, mentry: nil, if_etag: nil)
        writer = if container.respond_to?(:writer) && container.writer
                   container.writer.call(call)
                 else
                   Store::Envelope::Writer.from(container: @container, call: call)
                 end
        writer.delete(key, mentry: mentry, if_etag: if_etag)
      end

      def move(from_key:, to_key:, new_mentry:, call:, if_etag: nil)
        writer = if container.respond_to?(:writer) && container.writer
                   container.writer.call(call)
                 else
                   Store::Envelope::Writer.from(container: @container, call: call)
                 end
        writer.move(from_key: from_key, to_key: to_key, new_mentry: new_mentry, if_etag: if_etag)
      end

      def exists?(key)
        reader = if container.respond_to?(:reader) && container.reader
                   container.reader
                 else
                   Store::Envelope::Reader.from(container: @container)
                 end
        reader.exists?(key)
      end

      private

      def execute(command, call)
        handler = @registry.for(command.class)
        handler.call(command, call)
      end
    end
  end
end
