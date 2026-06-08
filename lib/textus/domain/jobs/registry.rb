module Textus
  module Domain
    module Jobs
      # Closed allow-list of runnable job types. The general `enqueue` surface
      # (a later phase) can only push types registered here — that is the safety
      # boundary that stops the "general runner" from running arbitrary code.
      class Registry
        Entry = Struct.new(:handler, :max_attempts, keyword_init: true)

        def initialize
          @entries = {}
        end

        def register(type, handler:, max_attempts: 3)
          @entries[type.to_s] = Entry.new(handler: handler, max_attempts: max_attempts)
        end

        def registered?(type)
          @entries.key?(type.to_s)
        end

        def lookup(type)
          @entries.fetch(type.to_s) do
            raise Textus::UsageError.new(
              "unregistered job type '#{type}'",
              hint: "register the type in Domain::Jobs::Registry before enqueueing it",
            )
          end
        end
      end
    end
  end
end
