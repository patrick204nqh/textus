module Textus
  module UseCases
    module Write
      class DeleteKey < Base
        handles Dispatch::Contracts::DeleteKey
        needs :file_system, :manifest, :audit_log, :layout, :writer, :reader

        def call
          writer.delete(command.key, if_etag: command.if_etag, call: @call)
          success("protocol" => Textus::PROTOCOL, "ok" => true, "key" => command.key, "deleted" => true)
        end
      end
    end
  end
end
