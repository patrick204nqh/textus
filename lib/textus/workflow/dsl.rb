module Textus
  module Workflow
    module DSL
      Step = Data.define(:name, :callable, :timeout)
      ValidateStep = Data.define(:name, :callable)
      Parallel = Data.define(:steps)

      class Definition
        attr_reader :name, :steps, :match_pattern, :publish_block, :validate_steps

        def initialize(name)
          @name           = name
          @steps          = []
          @validate_steps = []
          @match_pattern  = nil
          @publish_block  = nil
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

        def parallel(&)
          saved = @steps
          @steps = []
          instance_eval(&)
          parallel_steps = @steps.dup
          @steps = saved << Parallel.new(steps: parallel_steps)
        end

        def publish(&block)
          @publish_block = block || :default
        end

        def match?(key)
          return false unless @match_pattern && !@match_pattern.end_with?("**")

          Pattern.match?(@match_pattern, key)
        end

        # Returns true when this workflow should match MULTIPLE keys (glob pattern).
        def multi_match?
          @match_pattern&.end_with?("**")
        end

        # Returns true when this workflow has validation steps.
        def validation_workflow?
          @validate_steps.any?
        end
      end
    end
  end
end
