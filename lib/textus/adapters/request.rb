module Textus
  module Adapters
    Request = Data.define(:verb, :params, :role, :session_id, :correlation_id) do
      def initialize(verb:, params: {}, role: nil, session_id: nil, correlation_id: nil)
        super
      end
    end
  end
end
