module Textus
  module Handlers
    class DeleteKey
      def initialize(compositor:)
        @compositor = compositor
      end

      def call(command, call)
        @compositor.delete(command.key, call: call, if_etag: command.if_etag)
        Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "key" => command.key, "deleted" => true)
      end
    end
  end
end
