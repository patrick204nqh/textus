module Textus
  module Workflow
    module DSL
      Step = Data.define(:name, :callable, :timeout)
      ValidateStep = Data.define(:name, :callable)
      Parallel = Data.define(:steps)
      PublishTarget = Data.define(:to, :template, :tree, :inject_boot)

      class Definition
        include Textus::Workflow::Helpers

        attr_reader :name, :steps, :match_pattern, :publish_block, :publish_targets,
                    :validate_steps, :depends_on_patterns,
                    :handled_events, :max_attempts, :workflow_type

        def initialize(name)
          @name                = name
          @steps               = []
          @validate_steps      = []
          @match_pattern       = nil
          @publish_block       = nil
          @publish_targets     = []
          @priority            = 0
          @depends_on_patterns = []
          @ttl                 = nil
          @on_expire           = nil
          @handled_events      = []
          @max_attempts        = 3
          @workflow_type       = name
        end

        def handles(*event_types)
          @handled_events.concat(event_types.map(&:to_s).freeze)
        end

        def type
          @workflow_type
        end

        def match(pattern)
          @match_pattern = pattern
        end

        def step(name, callable_or_opt = nil, timeout: nil, &block)
          callable = if callable_or_opt.respond_to?(:call)
                       callable_or_opt
                     elsif block
                       block
                     else
                       raise ArgumentError.new("step :#{name} requires a block or a callable (got neither)")
                     end
          t = callable_or_opt.is_a?(Hash) ? callable_or_opt[:timeout] : timeout
          @steps << Step.new(name: name, callable: callable, timeout: t)
        end

        def validate(name, &block)
          @validate_steps << ValidateStep.new(name: name, callable: block)
        end

        def shape(key_pattern, naming:)
          @steps << Step.new(
            name: :"shape_#{key_pattern.tr(".*", "_")}",
            callable: lambda do |data, ctx|
              entries = ctx.container.manifest.resolver.enumerate.select do |row|
                Pattern.match?(key_pattern, row[:key].to_s)
              end

              new_issues = check_naming(
                entries,
                pattern: naming,
                code: "loop.naming",
                fix: "rename to match #{naming.inspect}",
              )
              existing_issues = Array(data&.dig("content", "issues"))
              issues = existing_issues + new_issues

              {
                "content" => {
                  "ok" => issues.empty?,
                  "issues" => issues,
                  "count" => issues.size,
                },
              }
            end,
            timeout: nil,
          )
        end

        def parallel(&)
          saved = @steps
          @steps = []
          instance_eval(&)
          parallel_steps = @steps.dup
          @steps = saved << Parallel.new(steps: parallel_steps)
        end

        def publish(to: nil, template: nil, tree: nil, inject_boot: nil, &block)
          if block
            @publish_block = block
          elsif to || tree
            @publish_targets << PublishTarget.new(to: to, template: template, tree: tree, inject_boot: inject_boot)
          else
            @publish_block = :default
          end
        end

        def priority(n = nil)
          return @priority if n.nil?

          @priority = n.to_i
        end

        def depends_on(pattern)
          @depends_on_patterns << pattern
        end

        def ttl(duration_string)
          @ttl = Textus::Value::Duration.seconds(duration_string)
        end

        def on_expire(action)
          actions = %i[drop archive]
          sym = action.to_s.to_sym
          raise ArgumentError.new("on_expire must be one of #{actions.join("|")}, got #{action.inspect}") unless actions.include?(sym)

          @on_expire = sym
        end

        def match?(key)
          return false unless @match_pattern && !@match_pattern.end_with?("**")

          Pattern.match?(@match_pattern, key)
        end

        def multi_match?
          @match_pattern&.end_with?("**")
        end

        def validation_workflow?
          @validate_steps.any?
        end
      end
    end
  end
end
