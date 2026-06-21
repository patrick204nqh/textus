# frozen_string_literal: true

module Textus
  class Gate
    VERB_ACTIONS = {
      get: [Textus::Action::Get],
      put: [Textus::Action::Put],
      propose: [Textus::Action::Propose],
      key_delete: [Textus::Action::KeyDelete],
      key_mv: [Textus::Action::KeyMv],
      accept: [Textus::Action::Accept],
      reject: [Textus::Action::Reject],
      enqueue: [Textus::Action::Enqueue],
      list: [Textus::Action::List],
      where: [Textus::Action::Where],
      uid: [Textus::Action::Uid],
      blame: [Textus::Action::Blame],
      audit: [Textus::Action::Audit],
      deps: [Textus::Action::Deps],
      rdeps: [Textus::Action::Rdeps],
      pulse: [Textus::Action::Pulse],
      rule_explain: [Textus::Action::RuleExplain],
      rule_list: [Textus::Action::RuleList],
      rule_lint: [Textus::Action::RuleLint],
      published: [Textus::Action::Published],
      schema_show: [Textus::Action::SchemaEnvelope],
      doctor: [Textus::Action::Doctor],
      boot: [Textus::Action::Boot],
      jobs: [Textus::Action::Jobs],
      data_mv: [Textus::Action::DataMv],
      key_mv_prefix: [Textus::Action::KeyMvPrefix],
      key_delete_prefix: [Textus::Action::KeyDeletePrefix],
      drain: [Textus::Action::Drain],
      ingest: [Textus::Action::Ingest],
    }.freeze

    def initialize(container)
      @container = container
    end

    def dispatch(spec:, inputs:, role:, correlation_id: nil, session: nil, surface: nil)
      resolved = Binder.bind(spec, inputs, session: session)
      cmd = Value::Command.new(verb: spec.verb, params: resolved.freeze, role: role)

      cmd = normalize_propose_key(cmd) if cmd.verb == :propose
      action_classes = VERB_ACTIONS.fetch(cmd.verb) do
        raise Textus::UsageError.new("unknown command verb: #{cmd.verb}")
      end

      auth = Gate::Auth.new(@container)
      auth.check!(cmd)
      check_dispatch_auth(cmd, resolved, auth)
      call_obj = build_call(cmd, correlation_id: correlation_id)
      results = action_classes.map { |klass| run_action(klass, resolved, call_obj) }
      result = results.length == 1 ? results.first : results
      cascade(cmd, result, call_obj) if CASCADE_VERBS.include?(cmd.verb) && !call_obj.dry_run
      return result unless surface

      spec.view(surface).call(result, resolved)
    end

    CASCADE_VERBS = %i[put propose accept reject key_mv key_delete].freeze

    AUTH_KEYS = {
      key_mv: ->(params) { [params[:old_key], params[:new_key]] },
      ingest: ->(params) { Textus::Action::Ingest.dispatch_key(**params) },
    }.freeze

    private

    def check_dispatch_auth(cmd, resolved, auth)
      return unless (resolver = AUTH_KEYS[cmd.verb])

      keys = Array(resolver.call(resolved))
      keys.each { |k| auth.check_action!(action: cmd.verb, actor: cmd.role, key: k) }
    end

    def normalize_propose_key(cmd)
      return cmd if cmd.pending_key

      zone = @container.manifest.policy.propose_lane_for(cmd.role.to_s)
      key = zone ? "#{zone}.#{cmd.key}" : nil
      cmd.with(params: cmd.params.merge(pending_key: key))
    end

    def run_action(klass, params, call_obj)
      result = klass.call(container: @container, call: call_obj, **params)
      unwrap_result(result)
    end

    def unwrap_result(result)
      case result
      when Dry::Monads::Result::Success then result.value!
      when Dry::Monads::Result::Failure
        failure = result.failure
        raise ActionError.new(
          failure[:code] || :internal,
          failure[:message] || "action failed",
          details: failure[:details] || {},
        )
      else result
      end
    end

    def build_call(cmd, correlation_id: nil)
      dry_run = cmd.params.key?(:dry_run) ? !cmd.params[:dry_run].nil? : false
      Textus::Value::Call.build(role: cmd.role, dry_run:, correlation_id: correlation_id)
    end

    def cascade(cmd, result, call)
      key = result.is_a?(Hash) ? result["cascade_key"] : nil
      key ||= cascade_key_from_params(cmd)
      return unless key

      rdeps = Textus::Action::Rdeps.call(container: @container, call: call, key: key).fetch("rdeps", [])
      producible = rdeps.select { |dep_key| producible?(dep_key) }
      producible.each do |dep_key|
        Textus::Store::Jobs::Materialize.call(container: @container, call: call, key: dep_key)
      end
    end

    def cascade_key_from_params(cmd)
      case cmd.verb
      when :put, :key_delete then cmd.params[:key]
      when :key_mv           then cmd.params[:new_key]
      when :propose, :reject then cmd.params[:pending_key]
      when :accept           then nil
      end
    end

    def producible?(key)
      entry = @container.manifest.resolver.resolve(key).entry
      !entry.publish_tree.nil?
    rescue Textus::Error
      false
    end
  end
end
