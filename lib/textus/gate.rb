# frozen_string_literal: true

require "securerandom"

module Textus
  class Gate
    ROUTES = {
      Command::Get => [Textus::Dispatch::Actions::Get],
      Command::Put => [Textus::Dispatch::Actions::Put],
      Command::Propose => [Textus::Dispatch::Actions::Propose],
      Command::KeyDelete => [Textus::Dispatch::Actions::KeyDelete],
      Command::KeyMv => [Textus::Dispatch::Actions::KeyMv],
      Command::Accept => [Textus::Dispatch::Actions::Accept],
      Command::Reject => [Textus::Dispatch::Actions::Reject],
      Command::Enqueue => [Textus::Dispatch::Actions::Enqueue],
      Command::List => [Textus::Dispatch::Actions::List],
      Command::Where => [Textus::Dispatch::Actions::Where],
      Command::Uid => [Textus::Dispatch::Actions::Uid],
      Command::Blame => [Textus::Dispatch::Actions::Blame],
      Command::Audit => [Textus::Dispatch::Actions::Audit],
      Command::Deps => [Textus::Dispatch::Actions::Deps],
      Command::Rdeps => [Textus::Dispatch::Actions::Rdeps],
      Command::Pulse => [Textus::Dispatch::Actions::Pulse],
      Command::RuleExplain => [Textus::Dispatch::Actions::RuleExplain],
      Command::RuleList => [Textus::Dispatch::Actions::RuleList],
      Command::RuleLint => [Textus::Dispatch::Actions::RuleLint],
      Command::Published => [Textus::Dispatch::Actions::Published],
      Command::SchemaShow => [Textus::Dispatch::Actions::SchemaEnvelope],
      Command::Doctor => [Textus::Dispatch::Actions::Doctor],
      Command::Boot => [Textus::Dispatch::Actions::Boot],
      Command::Jobs => [Textus::Dispatch::Actions::Jobs],
      Command::DataMv => [Textus::Dispatch::Actions::DataMv],
      Command::KeyMvPrefix => [Textus::Dispatch::Actions::KeyMvPrefix],
      Command::KeyDeletePrefix => [Textus::Dispatch::Actions::KeyDeletePrefix],
      Command::Drain => [Textus::Dispatch::Actions::Drain],
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
