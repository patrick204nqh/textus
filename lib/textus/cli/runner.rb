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

      # Map parsed CLI input -> (positional, keyword) for a spec. Positionals
      # are taken in contract declaration order from leftover argv; keyword args
      # come from declared flags. RoleScope fills contract literal defaults, so
      # absent optionals are omitted here. Required positionals that are absent
      # raise UsageError (parity with the hand-written verbs).
      def call_args(spec, positional_argv, flags)
        pos = []
        rest = positional_argv.dup
        kw = {}
        spec.args.each do |a|
          if a.positional
            val = rest.shift
            if val.nil?
              raise UsageError.new("#{spec.cli_path} requires #{a.wire}") if a.required

              next
            end
            pos << val
          elsif flags.key?(a.name)
            kw[a.name] = flags[a.name]
          end
        end
        [pos, kw]
      end

      def dispatch(verb_instance, store, spec)
        pos, kw = call_args(spec, verb_instance.positional, verb_instance.flag_values(spec))
        result = verb_instance.session_for(store).public_send(spec.verb, *pos, **kw)
        result = result.to_h_for_wire if result.respond_to?(:to_h_for_wire)
        shaper = spec.cli_response || spec.response
        verb_instance.emit(shaper.call(result))
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
      # escape hatches (behavior the generic runner can't express), the
      # custom-parse `fetch` family, the bulk *_prefix cousins (handled by the
      # single-key multi-dispatch classes), and category-C commands with custom
      # output (boot/doctor).
      #
      # The second row are verbs whose CLI surface emits a presentation envelope
      # the contract `response` does not (and must not — MCP would inherit it):
      # `{ "verb" => …, "rows"/"policies" => … }` (audit, freshness, rule_list,
      # rule_explain), `{ "entries" => … }` (list), `{ "key" =>, "uid" => }`
      # (uid), and pulse's session-cursor read/write. These stay hand-authored
      # until the contract grows a CLI-specific response facet (ADR 0063 follow-up).
      HAND_AUTHORED_VERBS = %i[
        get put propose build delete mv key_delete_prefix key_mv_prefix
        migrate rule_lint blame zone_mv fetch fetch_all boot doctor
        audit pulse uid
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
