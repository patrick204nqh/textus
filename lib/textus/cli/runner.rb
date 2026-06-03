module Textus
  class CLI
    # Generates CLI::Verb (and CLI::Group) subclasses from per-verb contracts,
    # so the CLI surface is a projection of the contract — the operator-facing
    # mirror of MCP::Catalog (ADR 0063).
    module Runner
      # Subclassable base for contract-projected verbs. Carries the verb's
      # contract (class attr `spec`) and the generic dispatch, exposing one
      # overridable seam, #invoke, that defaults to the generic projection.
      # Escape-hatch verbs subclass this and override #invoke to add behavior
      # (suggestions, --stdin, BuildLock, multi-dispatch) WITHOUT restating the
      # verb name — `spec.verb` remains the single source of dispatch.
      class Base < Verb
        class << self
          attr_accessor :spec

          # ADR 0064: derive the CLI command name from the contract's cli_leaf
          # when not set explicitly, so an escape-hatch class never restates its
          # own name. The reconciliation spec proves command_name == cli_leaf for
          # every such class, so this is an equivalence, not a behavior change.
          def command_name(name = nil)
            return super if name

            super() || spec&.cli_leaf
          end
        end

        def spec = self.class.spec

        def call(store)
          invoke(store)
        end

        # Default: pure contract projection. Override in subclasses for behavior.
        def invoke(store)
          Runner.dispatch(self, store, spec)
        end

        def flag_values(s = spec)
          s.args.reject(&:positional).each_with_object({}) do |a, h|
            raw = respond_to?(a.name) ? public_send(a.name) : nil
            next if raw.nil?

            h[a.name] = Runner.coerce(a, raw)
          end
        end
      end

      module_function

      # Normalize parsed CLI input into the uniform by-name inputs hash and
      # dispatch through RoleScope's single bind+invoke site. A missing required
      # arg becomes a UsageError phrased in the operator's command path (parity
      # with the hand-written verbs).
      def dispatch(verb_instance, store, spec)
        inputs = Textus::Contract::Binder.inputs_from_ordered(
          spec, verb_instance.positional, verb_instance.flag_values(spec)
        )
        inputs = inputs.merge(Textus::Contract::Sources.from_stdin(spec, verb_instance.stdin)) if spec.cli_stdin
        inputs = Textus::Contract::Sources.acquire(spec, inputs)
        scope = verb_instance.session_for(store)
        begin
          result = scope.dispatch_bound(spec.verb, inputs, validate: true)
        rescue Textus::Contract::MissingArgs => e
          raise UsageError.new("#{spec.cli_path} requires #{e.missing.first.wire}")
        end
        result = result.to_h_for_wire if result.respond_to?(:to_h_for_wire)
        verb_instance.emit(shape(spec, result, inputs))
      end

      # Shape the use-case result for the CLI wire via the verb's :cli view
      # (falling back to the default view). The view is called uniformly as
      # (result, inputs); an inputs-aware view echoes an input such as the key
      # (ADR 0067).
      def shape(spec, result, inputs)
        Textus::Contract::View.render(spec, :cli, result, inputs)
      end

      def flagspec_for(arg)
        wire = arg.wire.to_s.tr("_", "-")
        if arg.type == :boolean
          arg.default == true ? "--no-#{wire}" : "--#{wire}"
        else
          "--#{wire}=VALUE"
        end
      end

      def coerce(arg, raw)
        case arg.type
        when :boolean then arg.default != true
        when Integer  then Integer(raw)
        else raw
        end
      end

      def ensure_group(name)
        const = name.split("_").map(&:capitalize).join
        return Group.const_get(const, false) if Group.const_defined?(const, false)

        g = Class.new(Group) { command_name name }
        Group.const_set(const, g)
        g
      end

      # Verbs that keep a hand-authored CLI class and must NOT be generated:
      # genuine escape hatches the generic runner cannot express — stdin
      # (put/propose), file reads (migrate/rule_lint), stateful resources
      # (build/BuildLock, pulse/CursorStore), one-command-two-verbs multi-dispatch
      # (key delete/mv via --prefix), domain behavior (get's UnknownKey +
      # suggestions), and the bulk-destructive verbs whose CLI default differs
      # from their Ruby/MCP default (zone_mv applies by default on the CLI but
      # plans by default for agents, ADR 0060 — generating it would flip that).
      # `audit` stays for its `since` String→Time coercion and `**filters`
      # keyrest #call (ADR 0065 left it: converting one verb is not worth a
      # one-off `coerce:` primitive). Output-only hatches (uid, blame) became
      # generated verbs via arity-2 `cli_response` (ADR 0065).
      HAND_AUTHORED_VERBS = %i[
        get put build delete mv key_delete_prefix key_mv_prefix
        migrate rule_lint zone_mv fetch fetch_all boot doctor
        audit pulse
      ].freeze

      def hand_authored?(verb) = HAND_AUTHORED_VERBS.include?(verb)

      def install!
        @installed ||= {}
        Textus::Dispatcher::VERBS.each_value do |klass|
          next unless klass.respond_to?(:contract?) && klass.contract?

          spec = klass.contract
          next unless spec.cli?
          next if hand_authored?(spec.verb)
          next if @installed[spec.verb]

          install_for(spec)
          @installed[spec.verb] = true
        end
      end

      def install_for(spec)
        group = spec.cli_group ? ensure_group(spec.cli_group) : nil
        leaf  = spec.cli_leaf
        non_positional = spec.args.reject(&:positional)

        klass = Class.new(Base)
        klass.spec = spec
        klass.command_name leaf
        klass.parent_group group if group
        klass.option :as_flag, "--as=ROLE"
        klass.option :use_stdin, "--stdin" if spec.cli_stdin
        non_positional.each { |a| klass.option a.name, Runner.flagspec_for(a) }

        # Anchor the anonymous class to a constant so descendants discovery is
        # stable. Name it after the verb under a Generated namespace.
        const_name = spec.verb.to_s.split("_").map(&:capitalize).join
        gen = "Gen#{const_name}"
        Verb.const_set(gen, klass) unless Verb.const_defined?(gen, false)
        klass
      end
    end
  end
end
