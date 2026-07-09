module Textus
  class API
    class Session
      def initialize(id:, role:, correlation_id: nil, payload: {})
        @id = id
        @role = role
        @correlation_id = correlation_id || SecureRandom.uuid
        @payload = payload
      end

      attr_reader :id, :role, :correlation_id, :payload

      def agent?  = @role == "agent"
      def human?  = @role == "human"

      def with_payload(new_payload)
        self.class.new(id: @id, role: @role, correlation_id: @correlation_id, payload: new_payload)
      end
    end
  end
end
