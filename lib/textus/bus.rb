module Textus
  module Bus
    VERB_TO_CONTRACT = {
      get: Contracts::GetEntry,
      put: Contracts::PutEntry,
      list: Contracts::ListKeys,
      key_delete: Contracts::DeleteKey,
      key_mv: Contracts::MoveKey,
      propose: Contracts::ProposeEntry,
      accept: Contracts::AcceptProposal,
      reject: Contracts::RejectProposal,
      enqueue: Contracts::EnqueueJob,
      audit: Contracts::AuditEntries,
      pulse: Contracts::PulseEntries,
      blame: Contracts::BlameEntry,
      where: Contracts::WhereEntry,
      uid: Contracts::UidEntry,
      deps: Contracts::DepsEntry,
      rdeps: Contracts::RdepsEntry,
      boot: Contracts::BootStore,
      doctor: Contracts::DoctorStore,
      published: Contracts::PublishedEntries,
      rule_explain: Contracts::RuleExplain,
      rule_list: Contracts::RuleList,
      schema_show: Contracts::SchemaEnvelope,
      drain: Contracts::DrainStore,
      ingest: Contracts::IngestEntry,
      jobs: Contracts::JobsAction,
      rule_lint: Contracts::RuleLint,
      data_mv: Contracts::DataMv,
      key_mv_prefix: Contracts::KeyMvPrefix,
      key_delete_prefix: Contracts::KeyDeletePrefix,
    }.freeze

    CONTRACT_TO_VERB = VERB_TO_CONTRACT.invert.freeze

    module_function

    def contract_to_verb(klass)
      CONTRACT_TO_VERB[klass] || klass.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    def contract_to_verb!(klass)
      CONTRACT_TO_VERB.fetch(klass) do
        raise "unknown contract class: #{klass}"
      end
    end

    def dispatch(container:, spec:, inputs:, role:, correlation_id: nil, session: nil, surface: nil)
      contract_class = VERB_TO_CONTRACT.fetch(spec.verb) do
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
      when Textus::Result
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
      kwargs = members.each_with_object({}) do |m, h|
        h[m] = inputs[m]
      end
      contract_class.new(**kwargs)
    end
  end
end
