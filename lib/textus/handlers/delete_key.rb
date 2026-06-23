module Textus
  module Handlers
    class DeleteKey
      def initialize(container:)
        @container = container
      end

      def call(command, call)
        @container.pipeline.delete(command.key, call: call, if_etag: command.if_etag)
        Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "key" => command.key, "deleted" => true)
      end
    end
  end
end
