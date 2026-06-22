module Textus
  module Bus
    module Middleware
      class Audit < Base
        middleware_name :audit

        def initialize(audit_log)
          @audit_log = audit_log
        end

        def call(command, call, next_handler)
          result = next_handler.call(command)
          return result unless result.success?

          log(command, call, result.value)
          result
        end

        private

        def log(command, call, envelope)
          @audit_log.append(
            role: call.role, verb: verb_for(command.class),
            key: key_for(command),
            etag_before: nil,
            etag_after: envelope.respond_to?(:etag) ? envelope.etag : nil,
          )
        rescue StandardError
          nil
        end

        CONTRACT_TO_VERB = {
          Contracts::GetEntry => "get",
          Contracts::PutEntry => "put",
          Contracts::ListKeys => "list",
          Contracts::DeleteKey => "key_delete",
          Contracts::MoveKey => "key_mv",
          Contracts::ProposeEntry => "propose",
          Contracts::AcceptProposal => "accept",
          Contracts::RejectProposal => "reject",
          Contracts::EnqueueJob => "enqueue",
          Contracts::AuditEntries => "audit",
          Contracts::PulseEntries => "pulse",
          Contracts::BlameEntry => "blame",
          Contracts::WhereEntry => "where",
          Contracts::UidEntry => "uid",
          Contracts::DepsEntry => "deps",
          Contracts::RdepsEntry => "rdeps",
          Contracts::BootStore => "boot",
          Contracts::DoctorStore => "doctor",
          Contracts::PublishedEntries => "published",
          Contracts::RuleExplain => "rule_explain",
          Contracts::RuleList => "rule_list",
          Contracts::SchemaEnvelope => "schema_show",
          Contracts::DrainStore => "drain",
          Contracts::IngestEntry => "ingest",
          Contracts::JobsAction => "jobs",
          Contracts::RuleLint => "rule_lint",
          Contracts::DataMv => "data_mv",
          Contracts::KeyMvPrefix => "key_mv_prefix",
          Contracts::KeyDeletePrefix => "key_delete_prefix",
        }.freeze

        def verb_for(klass)
          CONTRACT_TO_VERB[klass] || klass.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        end

        def key_for(command)
          command.respond_to?(:key) ? command.key : command.respond_to?(:old_key) ? command.old_key : nil
        end
      end
    end
  end
end
