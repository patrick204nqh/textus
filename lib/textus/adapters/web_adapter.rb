module Textus
  module Adapters
    class WebAdapter
      def initialize(api:)
        @api = api
      end

      def call(action, params: {}, role: "agent", session_id: nil)
        session = session_id ? @api.resume_session(id: session_id) : @api.open_session(role:)
        @api.send(action, **params, session:)
      end
    end
  end
end
