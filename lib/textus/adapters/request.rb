module Textus
  module Adapters
    Request = Data.define(:action, :params, :role, :session_id, :correlation_id) do
      def initialize(action:, params: {}, role: nil, session_id: nil, correlation_id: nil)
        super
      end
    end
  end
end
