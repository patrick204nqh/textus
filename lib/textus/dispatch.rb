module Textus
  module Dispatch
    module_function

    def dispatch(container:, spec:, inputs:, role:, correlation_id: nil)
      VerbRegistry::VERB_TO_CONTRACT.fetch(spec.verb) do
        raise Textus::UsageError.new("unknown command verb: #{spec.verb}")
      end

      pending = Binder.command(spec, inputs)
      call = Value::Call.build(role: role.to_s, correlation_id: correlation_id || SecureRandom.uuid)
      result = container.pipeline.dispatch(pending, call: call)
      unwrap(result)
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
  end
end
