module Textus
  module Handlers
    class ProposeEntry
      def initialize(container:)
        @container = container
      end

      def call(command, call)
        zone = @container.manifest.policy.propose_lane_for(call.role)
        unless zone
          return Value::Result.failure(:propose_forbidden,
                                "role '#{call.role}' has no writable propose_lane",
                                details: { "role" => call.role })
        end

        key = "#{zone}.#{command.key}"
        mentry = @container.manifest.resolver.resolve(key).entry
        envelope = @container.pipeline.write(
          key, mentry: mentry, call: call,
               payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content)
        )
        Value::Result.success(envelope)
      end
    end
  end
end
