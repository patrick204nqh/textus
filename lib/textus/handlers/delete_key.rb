module Textus
  module Handlers
    class DeleteKey
      def initialize(container:)
        @container = container
      end

      def call(command, call)
        writer = Store::Entry::Writer.from(container: @container, call: call)
        writer.delete(command.key, if_etag: command.if_etag)
        Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "key" => command.key, "deleted" => true)
      end
    end
  end
end
