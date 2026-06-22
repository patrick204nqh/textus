# frozen_string_literal: true

module Textus
  class Gate
    def initialize(container)
      @container = container
    end

    def dispatch(spec:, inputs:, role:, correlation_id: nil, session: nil, surface: nil)
      resolved = Binder.bind(spec, inputs, session: session)
      cmd = Value::Command.new(verb: spec.verb, params: resolved.freeze, role: role)

      cmd = normalize_propose_key(cmd) if cmd.verb == :propose
      action_class = Textus::Action::VERBS.fetch(cmd.verb) do
        raise Textus::UsageError.new("unknown command verb: #{cmd.verb}")
      end

      auth = Gate::Auth.new(@container)
      auth.check!(cmd)
      check_dispatch_auth(cmd, resolved, auth)
      call_obj = build_call(cmd, correlation_id: correlation_id)
      result = run_action(action_class, resolved, call_obj)
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
      Value::Result.unwrap(result)
    end

    def build_call(cmd, correlation_id: nil)
      dry_run = cmd.params.key?(:dry_run) ? !cmd.params[:dry_run].nil? : false
      Textus::Value::Call.build(role: cmd.role, dry_run:, correlation_id: correlation_id)
    end

    def cascade(cmd, result, call)
      key = result.is_a?(Hash) ? result["cascade_key"] : nil
      key ||= cascade_key_from_params(cmd)
      return unless key

      rdeps_result = Textus::Action::Rdeps.call(container: @container, call: call, key: key)
      rdeps = Value::Result.unwrap(rdeps_result).fetch("rdeps", [])
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
