module Textus
  module Adapters
    class McpAdapter
      def initialize(api:)
        @api = api
        @session_id = nil
      end

      def call(action, params: {}, role: "agent", session_id: nil)
        @session_id = session_id || @session_id

        session = @session_id ? @api.resume_session(id: @session_id) : @api.open_session(role:)
        @session_id ||= session.id

        str_params = deep_stringify_keys(params)
        @api.send(action, **str_params.transform_keys(&:to_sym), session:)
      end

      private

      def deep_stringify_keys(obj)
        case obj
        when Hash  then obj.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
        when Array then obj.map { |v| deep_stringify_keys(v) }
        else obj
        end
      end
    end
  end
end
