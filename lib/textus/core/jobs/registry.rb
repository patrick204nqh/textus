module Textus
  module Core
    module Jobs
      # Closed allow-list of runnable job types. The general `enqueue` surface
      # (a later phase) can only push types registered here — that is the safety
      # boundary that stops the "general runner" from running arbitrary code.
      class Registry
        Entry = Struct.new(:handler, :max_attempts, :required_role, keyword_init: true)

        def initialize
          @entries = {}
        end

        # required_role: a role the caller must hold to enqueue this type via the
        # general `enqueue` surface (nil = any caller). The closed allow-list is
        # the primary safety boundary; this is defence-in-depth for destructive
        # types.
        def register(type, handler:, max_attempts: 3, required_role: nil)
          @entries[type.to_s] = Entry.new(handler: handler, max_attempts: max_attempts, required_role: required_role)
        end

        def registered?(type)
          @entries.key?(type.to_s)
        end

        def lookup(type)
          @entries.fetch(type.to_s) do
            raise Textus::UsageError.new(
              "unregistered job type '#{type}'",
              hint: "register the type in Core::Jobs::Registry before enqueueing it",
            )
          end
        end
      end
    end
  end
end
