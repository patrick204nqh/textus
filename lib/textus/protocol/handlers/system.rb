module Textus
  module Protocol
    module Handlers
      module System
        include Concern
        extend self

        def boot(ctx:, call:)
          proxy = Textus::Protocol::Container.new(
            store: ctx.container.store,
            layout: ctx.layout,
            manifest: ctx.manifest, schemas: ctx.schemas,
            workflows: nil,
            root: ctx.layout.root
          )
          Textus::Protocol::Boot.build(container: proxy)
        end

        def audit(ctx:, call:, key: nil, lane: nil, role: nil, verb: nil, since: nil, seq_since: nil, correlation_id: nil, limit: nil)
          Ops::AuditFilter.new.call(
            ctx:,
            key:, lane:, role:, verb:,
            since:, seq_since:, correlation_id:, limit:
          )
        end

        def blame(key:, ctx:, call:)
          audit_result = audit(key:, ctx:, call:)
          audit_rows = audit_result["rows"] || []
          git_map = Ops::GitBlame.new.call(key:, ctx:)
          audit_rows.map { |row| row.merge("git" => git_map ? git_map[row["ts"]] : nil) }
        end

        def pulse(ctx:, call:, since: nil)
          Ops::PulseCoordinator.new.call(role: call.role, ctx:, since:)
        end

        def workflow_spec(name:, ctx:, call:)
          registry = ctx.workflow_registry || Textus::Workflow::Registry.new(ctx.workflows)
          wf = registry.for(name)
          {
            "name" => wf.name, "type" => wf.workflow_type,
            "match_patterns" => wf.match_pattern ? [wf.match_pattern] : [],
            "handles_events" => wf.handled_events,
            "steps" => wf.steps.map { |s| { "name" => s.name.to_s, "type" => step_type(s) } },
            "publish_targets" => wf.publish_targets.map do |t|
              h = {}
              h["to"] = t.to if t.to
              h["template"] = t.template if t.template
              h
            end,
            "priority" => wf.priority,
            "max_attempts" => wf.max_attempts,
            "depends_on" => wf.depends_on_patterns,
            "ttl" => wf.ttl ? wf.ttl.to_s : nil,
            "on_expire" => wf.on_expire
          }
        end

        def drain(ctx:, call:)
          registry = ctx.workflow_registry || Textus::Workflow::Registry.new(ctx.workflows)
          result = Textus::Protocol::Events::Consumer.new.drain(
            workflow_queue: ctx.workflow_queue, registry:, container: ctx.container, call:,
          )
          { "protocol" => Textus::PROTOCOL, "ok" => result[:failed].zero?,
            "completed" => result[:completed], "failed" => result[:failed] }
        end

        private

        def step_type(step)
          case step
          when Textus::Workflow::DSL::ValidateStep then "validate"
          when Textus::Workflow::DSL::Parallel then "parallel"
          else "step"
          end
        end
      end
    end
  end
end
