module Textus
  module Adapters
    class WebAdapter
      def call(verb, params: {}, role: nil, gate:, session_id: nil)
        request = Request.new(
          verb: verb.to_s.to_sym,
          params: params.transform_keys(&:to_sym),
          role: role,
          session_id: session_id,
        )
        gate.dispatch(request)
      end

      def normalize(raw)
        verb = raw.delete("verb").to_s.to_sym
        role = raw.delete("role")&.to_s
        session_id = raw.delete("session_id")
        Request.new(verb:, params: raw.transform_keys(&:to_sym), role:, session_id:)
      end
    end
  end
end
