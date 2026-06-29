module Textus
  module Handlers
    module Read
      class UidEntry
        def initialize(container:)
          @container = container
        end

        def call(command, _call)
          envelope = Store::Entry::Reader.from(container: @container).read(command.key)
          return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

          Value::Result.success(envelope.uid)
        end
      end
    end
  end
end
