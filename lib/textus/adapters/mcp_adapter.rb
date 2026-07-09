module Textus
  module Adapters
    class McpAdapter
      def call(method, params: {}, gate:, role: nil, session_id: nil)
        spec = Textus::Protocol::VerbRegistry.for(method.to_s.to_sym)
        str_params = deep_stringify_keys(params || {})
        bound = if spec
                  Textus::Protocol::Binder.inputs_from_wire(spec, str_params)
                else
                  str_params.transform_keys(&:to_sym)
                end

        request = Request.new(
          verb: method.to_s.to_sym,
          params: bound,
          role: role,
          session_id: session_id,
        )
        gate.dispatch(request)
      end

      def normalize(raw)
        spec = Textus::Protocol::VerbRegistry.for(raw["method"].to_s.to_sym)
        str_params = deep_stringify_keys(raw["params"] || {})
        bound = if spec
                  Textus::Protocol::Binder.inputs_from_wire(spec, str_params)
                else
                  str_params.transform_keys(&:to_sym)
                end

        Request.new(
          verb: raw["method"].to_s.to_sym,
          params: bound,
          role: raw["role"],
          session_id: raw["session_id"],
        )
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
