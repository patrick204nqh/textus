require "open3"

module Textus
  module Protocol
    module Handlers
      module System
        include Concern
        extend self

        def boot(store:, ctx:, call:)
          proxy = Textus::Protocol::Container.new(
            store: ctx.container.store,
            layout: ctx.layout,
            manifest: ctx.manifest, schemas: ctx.schemas,
            workflows: nil,
            root: ctx.layout.root
          )
          Textus::Protocol::Boot.build(container: proxy)
        end

        def audit(store:, ctx:, call:, key: nil, lane: nil, role: nil, verb: nil, since: nil, seq_since: nil, correlation_id: nil, limit: nil)
          if seq_since
            min = store.audit_log.min_available
            raise Textus::CursorExpired.new(requested: seq_since, min_available: min) if min && seq_since < min - 1
          end
          rows = store.audit_log.list(seq_since:, key:, role:, verb:, correlation_id:, limit:).select do |row|
            next false if lane && !key_in_lane?(row["key"], lane, store)
            next false if since && row["ts"] && Time.parse(row["ts"]) < since

            true
          end
          { "verb" => "audit", "rows" => rows }
        end

        def blame(key:, store:, ctx:, call:)
          audit_result = audit(key:, store:, ctx:, call:)
          audit_rows = audit_result["rows"] || []
          root = ctx.manifest.data.root
          path = resolve_blame_path(key, store)
          return audit_rows.map { |row| row.merge("git" => nil) } unless git_tracked?(path, root:)

          audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"], root:)) }
        end

        def pulse(store:, ctx:, call:, since: nil)
          cursor_val = since || store.cursor_store.get(call.role)[:seq]
          audit_result = audit(seq_since: cursor_val, store:, ctx:, call:)
          changed = audit_result["rows"] || []
          queue = ctx.manifest.policy.queue_lane
          pending = queue ? store.list(lane: queue) : []
          runner = Textus::Lanes::Knowledge::Runner.new(ctx.manifest, cursor_store: store.cursor_store)
          result = {
            "cursor" => store.audit_log.latest[:seq],
            "changed" => changed,
            "pending_review" => pending.is_a?(Array) ? pending.map { |r| r["key"] } : [],
            "contract_etag" => Textus::Value::Etag.for_contract(ctx.layout),
            "index_etag" => pulse_index_etag(store),
            "loop_state" => runner.current_position(call.role),
          }
          store.cursor_store.set(call.role, result["cursor"])
          result
        end

        def workflow_spec(name:, store:, ctx:, call:)
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

        def drain(store:, ctx:, call:)
          registry = ctx.workflow_registry || Textus::Workflow::Registry.new(ctx.workflows)
          result = Textus::Protocol::Events::Consumer.new.drain(
            workflow_queue: store.workflow_queue, registry:, container: ctx.container, call:,
          )
          { "protocol" => Textus::PROTOCOL, "ok" => result[:failed].zero?,
            "completed" => result[:completed], "failed" => result[:failed] }
        end

        private

        def key_in_lane?(key, lane_name, store)
          mentry = store.mentry_for(key:)
          mentry && mentry.lane == lane_name
        rescue Textus::Error
          false
        end

        def resolve_blame_path(key, store)
          res = store.resolve(key:)
          res.path || Textus::Protocol::Key::Path.resolve(store.manifest.data, res.entry)
        rescue Textus::Error
          nil
        end

        def git_tracked?(path, root:)
          return false if path.nil? || !File.exist?(path) || !git_repo?(root)

          _out, _err, status = Open3.capture3("git", "ls-files", "--error-unmatch", path, chdir: root)
          status.success?
        rescue Errno::ENOENT
          false
        end

        def git_repo?(root)
          dir = root
          loop do
            return true if File.directory?(File.join(dir, ".git"))

            parent = File.dirname(dir)
            return false if parent == dir

            dir = parent
          end
        end

        def git_commit_at(path, timestamp:, root:)
          args = ["git", "log", "-1"]
          args << "--before=#{timestamp}" if timestamp
          args += ["--format=%H%x09%an%x09%aI%x09%s", "--", path]
          out, _err, status = Open3.capture3(*args, chdir: root)
          return nil unless status.success?

          sha, author, date, subject = out.strip.split("\t", 4)
          return nil if sha.nil? || sha.empty?

          { "sha" => sha, "author" => author, "date" => date, "subject" => subject }
        rescue Errno::ENOENT
          nil
        end

        def pulse_index_etag(store)
          path = store.resolve(key: "artifacts.system.index").path
          File.exist?(path) ? store.file_system.etag(path) : nil
        rescue Textus::Error
          nil
        end

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
