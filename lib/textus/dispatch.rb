module Textus
  module Dispatch
    module_function

    def dispatch(container:, spec:, inputs:, role:, correlation_id: nil, session: nil, surface: nil)
      contract_class = VerbRegistry::VERB_TO_CONTRACT.fetch(spec.verb) do
        raise Textus::UsageError.new("unknown command verb: #{spec.verb}")
      end

      resolved = Binder.bind(spec, inputs, session: session)
      command = build_command(contract_class, resolved)
      call = Value::Call.build(role: role.to_s, correlation_id: correlation_id || SecureRandom.uuid)
      result = container.pipeline.dispatch(command, call: call)
      result = unwrap(result)
      return result unless surface

      spec.view(surface).call(result, resolved)
    end

    def unwrap(result)
      return result if result.is_a?(Hash) || result.is_a?(Array) || result.nil? || result == true || result == false

      case result
      when Value::Result
        if result.success?
          result.value
        else
          err = result.error
          raise ActionError.new(err[:code] || :error, err[:message] || "action failed", details: err[:details] || {})
        end
      else
        result
      end
    end

    def build_command(contract_class, inputs)
      members = contract_class.members
      kwargs = members.to_h do |m|
        [m, inputs[m]]
      end
      contract_class.new(**kwargs)
    end
  end
end
