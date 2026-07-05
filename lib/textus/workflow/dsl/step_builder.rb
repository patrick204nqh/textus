module Textus
  module Workflow
    module DSL
      module StepBuilder
        def build_step(name, callable = nil, timeout: nil, &block)
          if callable.is_a?(Hash)
            raise ArgumentError.new(
              "step :#{name} no longer accepts options hash; pass timeout: keyword instead",
            )
          end

          resolved = if callable.respond_to?(:call)
                       callable
                     elsif block
                       block
                     else
                       raise ArgumentError.new("step :#{name} requires a block or a callable (got neither)")
                     end

          Step.new(name: name, callable: resolved, timeout: timeout)
        end

        def build_check(name, naming: nil, scope: nil, &block)
          merge = ->(data, new_issues) {
            existing = Array(data&.dig("content", "issues"))
            all = existing + new_issues
            { "content" => { "ok" => all.empty?, "issues" => all, "count" => all.size } }
          }

          if naming
            raise ArgumentError.new("check :#{name} requires a scope: for naming checks") unless scope

            ->(data, ctx) {
              entries = ctx.container.manifest.resolver.enumerate.select do |row|
                match_pattern?(scope, row[:key].to_s)
              end
              new_issues = check_naming(
                entries, pattern: naming, code: "check.#{name}",
                fix: "rename to match #{naming.inspect}",
              )
              merge.call(data, new_issues)
            }
          elsif block
            ->(data, ctx) { merge.call(data, block.call(ctx) || []) }
          else
            raise ArgumentError.new("check :#{name} requires naming: or a block")
          end
        end

        def build_parallel(steps)
          Parallel.new(steps: steps)
        end
      end
    end
  end
end
