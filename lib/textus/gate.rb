# frozen_string_literal: true

require "securerandom"

module Textus
  class Gate
    ROUTES = {
      Command::Get => [Textus::Action::Get],
      Command::Put => [Textus::Action::Put],
      Command::Propose => [Textus::Action::Propose],
      Command::KeyDelete => [Textus::Action::KeyDelete],
      Command::KeyMv => [Textus::Action::KeyMv],
      Command::Accept => [Textus::Action::Accept],
      Command::Reject => [Textus::Action::Reject],
      Command::Enqueue => [Textus::Action::Enqueue],
      Command::List => [Textus::Action::List],
      Command::Where => [Textus::Action::Where],
      Command::Uid => [Textus::Action::Uid],
      Command::Blame => [Textus::Action::Blame],
      Command::Audit => [Textus::Action::Audit],
      Command::Deps => [Textus::Action::Deps],
      Command::Rdeps => [Textus::Action::Rdeps],
      Command::Pulse => [Textus::Action::Pulse],
      Command::RuleExplain => [Textus::Action::RuleExplain],
      Command::RuleList => [Textus::Action::RuleList],
      Command::RuleLint => [Textus::Action::RuleLint],
      Command::Published => [Textus::Action::Published],
      Command::SchemaShow => [Textus::Action::SchemaEnvelope],
      Command::Doctor => [Textus::Action::Doctor],
      Command::Boot => [Textus::Action::Boot],
      Command::Jobs => [Textus::Action::Jobs],
      Command::DataMv => [Textus::Action::DataMv],
      Command::KeyMvPrefix => [Textus::Action::KeyMvPrefix],
      Command::KeyDeletePrefix => [Textus::Action::KeyDeletePrefix],
      Command::Drain => [Textus::Action::Drain],
    }.freeze

    def initialize(container)
      @container = container
    end

    def dispatch(cmd, container: @container)
      action_classes = ROUTES.fetch(cmd.class) do
        raise Textus::UsageError.new("unknown command: #{cmd.class}")
      end

      Gate::Auth.new(container).check!(cmd)
      call_obj = build_call(cmd)
      results = action_classes.map { |klass| run_action(klass, cmd, container, call_obj) }
      results.one? ? results.first : results
    end

    private

    def run_action(klass, cmd, container, call_obj)
      action = klass.new(**extract_kwargs(cmd))
      record_audit(cmd, call_obj, container)
      action.call(container:, call: call_obj)
    end

    def extract_kwargs(cmd)
      cmd.members.reject { |m| m == :role }.each_with_object({}) do |m, h|
        val = cmd.public_send(m)
        h[m] = val unless val.nil?
      end
    end

    def build_call(cmd)
      dry_run = cmd.respond_to?(:dry_run) ? !cmd.dry_run.nil? : false
      Textus::Call.build(role: cmd.role, dry_run:)
    end

    def record_audit(cmd, call_obj, container)
      key = cmd.respond_to?(:key) ? cmd.key : nil
      verb = cmd.class.name.split("::").last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      container.audit_log.append(
        role: cmd.role,
        verb:,
        key:,
        etag_before: nil,
        etag_after: nil,
        extras: { "correlation_id" => call_obj.correlation_id }.compact,
      )
    rescue StandardError => e
      warn "[Textus::Gate] audit write failed: #{e.message}"
    end
  end
end
