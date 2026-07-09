module Textus
  module Adapters
    class WebAdapter
      def call(action, params: {}, role: nil, gate:, session_id: nil)
        request = Request.new(
          action: action.to_s.to_sym,
          params: params.transform_keys(&:to_sym),
          role: role,
          session_id: session_id,
        )
        gate.dispatch(request)
      end

      def normalize(raw)
        action = raw.delete("action").to_s.to_sym
        role = raw.delete("role")&.to_s
        session_id = raw.delete("session_id")
        Request.new(action:, params: raw.transform_keys(&:to_sym), role:, session_id:)
      end
    end
  end
end
