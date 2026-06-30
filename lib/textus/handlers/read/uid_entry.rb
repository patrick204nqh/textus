module Textus
  module Handlers
    module Read
      module UidEntry
        HANDLES = Dispatch::Contracts::UidEntry
        NEEDS   = %i[file_store manifest layout].freeze

        def self.call(command, _call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          envelope = reader.read(command.key)
          return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

          Value::Result.success(envelope.uid)
        end
      end
    end
  end
end
