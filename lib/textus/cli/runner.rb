module Textus
  class CLI
    # Generates CLI::Verb (and CLI::Group) subclasses from per-verb contracts,
    # so the CLI surface is a projection of the contract — the operator-facing
    # mirror of MCP::Catalog (ADR 0063).
    module Runner
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
        verb_instance.emit(spec.response.call(result))
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

      # Verbs that keep a hand-authored class (escape hatches / category-C).
      # During THIS spike, everything except `where` is hand-authored, so the
      # runner only generates `where`. (Later tasks expand the generated set.)
      def generated_verbs
        %i[where]
      end

      def install!
        @installed ||= {}
        Textus::Dispatcher::VERBS.each_value do |klass|
          next unless klass.respond_to?(:contract?) && klass.contract?

          spec = klass.contract
          next unless spec.cli?
          next unless generated_verbs.include?(spec.verb)
          next if @installed[spec.verb]

          install_for(spec)
          @installed[spec.verb] = true
        end
      end

      def install_for(spec)
        group = spec.cli_group ? ensure_group(spec.cli_group) : nil
        leaf  = spec.cli_leaf
        non_positional = spec.args.reject(&:positional)

        klass = Class.new(Verb) do
          command_name leaf
          parent_group group if group
          option :as_flag, "--as=ROLE"
          non_positional.each { |a| option a.name, Runner.flagspec_for(a) }

          define_method(:flag_values) do |s|
            s.args.reject(&:positional).each_with_object({}) do |a, h|
              raw = respond_to?(a.name) ? public_send(a.name) : nil
              next if raw.nil?

              h[a.name] = Runner.coerce(a, raw)
            end
          end

          define_method(:call) { |store| Runner.dispatch(self, store, spec) }
        end

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
