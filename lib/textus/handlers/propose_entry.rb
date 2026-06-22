module Textus
  module Handlers
    class ProposeEntry
      def initialize(compositor:)
        @compositor = compositor
      end

      def call(command, call)
        zone = @compositor.manifest.policy.propose_lane_for(call.role)
        unless zone
          return Result.failure(:propose_forbidden,
            "role '#{call.role}' has no writable propose_lane",
            details: { "role" => call.role })
        end

        key = "#{zone}.#{command.key}"
        mentry = @compositor.manifest.resolver.resolve(key).entry
        envelope = @compositor.write(key, mentry: mentry,
          payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content),
          call: call)
        Result.success(envelope)
      end
    end
  end
end
