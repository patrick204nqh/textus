module Textus
  module Protocol
    module Handlers
      extend self

      def get(key:, ctx:, call:)
        env = ctx.read(key)
        unless env
          suggestions = ctx.manifest.resolver.suggestions_for(key)
          raise Textus::UnknownKey.new(key, suggestions:)
        end

        expand_sources(env, ctx, depth: 0).to_h_for_wire
      end

      def put(key:, ctx:, call:, meta: nil, body: nil, content: nil, if_etag: nil)
        env = ctx.write(key,
                        mentry: ctx.mentry_for(key),
                        payload: ctx.payload(meta: meta || {}, body:, content:),
                        if_etag:, call:)
        { "uid" => env.uid, "etag" => env.etag }
      end

      def list(ctx:, call:, prefix: nil, lane: nil, q: nil, schema: nil)
        if ctx.entry_index && (q || schema)
          rows = ctx.list(prefix:, lane:, q:, schema:)
          (rows || []).map { |r| { "key" => r["key"], "lane" => r["lane"] } }
        else
          rows = ctx.manifest.resolver.enumerate(prefix:)
          rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
          rows.map { |row| { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] } }
        end
      end

      def delete(key:, ctx:, call:, if_etag: nil)
        ctx.delete(key, if_etag:, call:)
        { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
      end
      alias key_delete delete

      def where(key:, ctx:, call:)
        res = ctx.resolve(key)
        { "protocol" => Textus::PROTOCOL, "key" => key, "lane" => res.entry.lane, "path" => res.path }
      end

      def uid(key:, ctx:, call:)
        env = ctx.read(key)
        raise Textus::UnknownKey.new(key) unless env

        env.uid
      end

      def move(old_key:, new_key:, ctx:, call:, if_etag: nil, dry_run: false)
        Textus::Protocol::Manifest::Data.validate_key!(old_key)
        Textus::Protocol::Manifest::Data.validate_key!(new_key)
        raise Textus::UsageError.new("old and new keys are identical") if old_key == new_key

        old_res = ctx.resolve(old_key)
        new_res = ctx.resolve(new_key)

        raise Textus::UnknownKey.new(old_key) unless ctx.exists?(old_key)
        raise Textus::UsageError.new("target '#{new_key}' already exists") if ctx.exists?(new_key)
        unless old_res.entry.lane == new_res.entry.lane
          raise Textus::UsageError.new("cross-zone moves forbidden (#{old_res.entry.lane} → #{new_res.entry.lane})")
        end

        pre_env = ctx.read(old_key)
        unless pre_env.uid
          ctx.write(old_key, mentry: old_res.entry, call:,
                             payload: ctx.payload(meta: pre_env.meta, body: pre_env.body, content: pre_env.content))
        end

        if dry_run
          return { "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => true,
                   "from_key" => old_key, "to_key" => new_key,
                   "from_path" => old_res.path, "to_path" => new_res.path, "uid" => pre_env.uid }
        end

        envelope = ctx.move(from_key: old_key, to_key: new_key, new_mentry: new_res.entry, call:)
        { "protocol" => Textus::PROTOCOL, "ok" => true, "from_key" => old_key, "to_key" => new_key,
          "from_path" => old_res.path, "to_path" => new_res.path, "uid" => envelope.uid, "envelope" => envelope.to_h_for_wire }
      end

      def deps(key:, ctx:, call:)
        entry = ctx.manifest.data.entries.find { |e| e.key == key }
        deps_list = entry&.external? ? Array(entry.source&.sources).compact : []
        { "key" => key, "deps" => deps_list.uniq }
      end

      def rdeps(key:, ctx:, call:)
        source_rdeps = ctx.manifest.data.entries.each_with_object([]) do |entry, acc|
          next unless entry.external?

          sources = Array(entry.source&.sources).compact
          acc << entry.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
        end
        link_rdeps = ctx.links.links_to(key)
        { "key" => key, "rdeps" => (source_rdeps + link_rdeps).uniq.sort }
      end

      def graph(key:, ctx:, call:, depth: nil)
        from = ctx.links.links_from(key)
        to   = ctx.links.links_to(key)
        { "key" => key, "neighbors" => (from + to).uniq.sort,
          "reachable" => ctx.links.reachable(from: key, depth:).sort }
      end

      def boot(ctx:, call:)
        proxy = Textus::Protocol::Container.new(
          store: ctx.store,
          layout: ctx.layout,
          manifest: ctx.manifest, schemas: ctx.schemas,
          workflows: nil,
          root: ctx.layout.root
        )
        Textus::Protocol::Boot.build(container: proxy)
      end

      def schema_show(key:, ctx:, call:)
        mentry = ctx.mentry_for(key)
        schema = ctx.schemas.fetch_or_nil(mentry.schema)
        { "protocol" => Textus::PROTOCOL, "key" => key,
          "schema_ref" => mentry.schema, "schema" => schema&.to_h }
      end

      def audit(ctx:, call:, key: nil, lane: nil, role: nil, verb: nil, since: nil, seq_since: nil, correlation_id: nil, limit: nil)
        if seq_since
          min = ctx.audit.min_available_seq
          raise Textus::CursorExpired.new(requested: seq_since, min_available: min) if min && seq_since < min - 1
        end
        rows = ctx.audit.scan(seq_since:, key:, role:, verb:, correlation_id:, limit:).select do |row|
          next false if lane && !key_in_lane?(row["key"], lane, ctx)
          next false if since && row["ts"] && Time.parse(row["ts"]) < since

          true
        end
        { "verb" => "audit", "rows" => rows }
      end

      def blame(key:, ctx:, call:)
        audit_result = audit(key:, ctx:, call:)
        audit_rows = audit_result["rows"] || []
        root = ctx.manifest.data.root
        path = resolve_blame_path(key, ctx)
        return audit_rows.map { |row| row.merge("git" => nil) } unless git_tracked?(path, root:)

        audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"], root:)) }
      end

      def pulse(ctx:, call:, since: nil)
        cursor_val = since || ctx.store.cursor_store.read(call.role)
        audit_result = audit(seq_since: cursor_val, ctx:, call:)
        changed = audit_result["rows"] || []
        queue = ctx.manifest.policy.queue_lane
        pending = queue ? list(lane: queue, ctx:, call:) : []
        runner = Lanes::Knowledge::Runner.new(ctx.manifest, cursor_store: ctx.store.cursor_store)
        result = {
          "cursor" => ctx.audit.latest_seq,
          "changed" => changed,
          "pending_review" => pending.is_a?(Array) ? pending.map { |r| r["key"] } : [],
          "contract_etag" => Textus::Value::Etag.for_contract(ctx.layout),
          "index_etag" => pulse_index_etag(ctx),
          "loop_state" => runner.current_position(call.role),
        }
        ctx.store.cursor_store.write(call.role, result["cursor"])
        result
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
          event_store: ctx.event_store, registry:, container: ctx.container, call:,
        )
        { "protocol" => Textus::PROTOCOL, "ok" => result[:failed].zero?,
          "completed" => result[:completed], "failed" => result[:failed] }
      end

      def key_mv_prefix(from_prefix:, to_prefix:, ctx:, call:, dry_run: false)
        raise Textus::UsageError.new("from_prefix and to_prefix required") unless from_prefix && to_prefix

        leaves = list(prefix: from_prefix, ctx:, call:)
        raise Textus::UsageError.new("from_prefix is a leaf — use mv") if leaves.any? { |r| r["key"] == from_prefix }

        warnings = leaves.empty? ? ["no keys under #{from_prefix}"] : []
        steps = leaves.map do |row|
          tail = row["key"].delete_prefix("#{from_prefix}.")
          { "op" => "mv", "from" => row["key"], "to" => "#{to_prefix}.#{tail}" }
        end
        plan = Textus::Protocol::Retention::Plan.new(steps:, warnings:)
        return plan.to_h if dry_run

        steps.each { |s| move(old_key: s["from"], new_key: s["to"], ctx:, call:) }
        plan.to_h
      end

      def key_delete_prefix(prefix:, ctx:, call:, dry_run: false)
        raise Textus::UsageError.new("prefix required") unless prefix && !prefix.empty?

        leaves = list(prefix:, ctx:, call:)

        warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
        steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }
        plan = Textus::Protocol::Retention::Plan.new(steps:, warnings:)
        return plan.to_h if dry_run

        steps.each { |s| delete(key: s["key"], ctx:, call:) }
        plan.to_h
      end

      def data_mv(from:, to:, ctx:, call:, dry_run: false)
        raise Textus::UsageError.new("from and to required") unless from && to
        raise Textus::UsageError.new("data lane '#{from}' not declared") unless ctx.manifest.data.declared_lane_kinds.key?(from)

        dest_dir = ctx.layout.lane_path(to)
        raise Textus::UsageError.new("destination data/#{to} already exists") if File.exist?(dest_dir)

        affected_keys = ctx.manifest.data.entries.select { |e| e.lane == from }.map(&:key)
        steps = [{ "op" => "rename_zone", "from" => from, "to" => to }]
        steps += affected_keys.map { |k| { "op" => "mv", "from" => k, "to" => "#{to}#{k[from.length..]}" } }
        plan = Textus::Protocol::Retention::Plan.new(steps:, warnings: [])
        return plan.to_h if dry_run

        rewrite_data_mv_manifest!(from:, to:, ctx:)
        FileUtils.mv(ctx.layout.lane_path(from), dest_dir)
        plan.to_h
      end

      def step_type(step)
        case step
        when Textus::Workflow::DSL::ValidateStep then "validate"
        when Textus::Workflow::DSL::Parallel then "parallel"
        else "step"
        end
      end

      private

      def expand_sources(envelope, ctx, depth:)
        return envelope if depth >= 5

        raw_sources = Array(envelope.meta["sources"])
        return envelope if raw_sources.empty?

        expanded = raw_sources.map { |src| expand_one_source(src, ctx, depth:) }
        envelope.with(sources: expanded)
      end

      def expand_one_source(src, ctx, depth:)
        src = { "key" => src } if src.is_a?(String)
        return src unless src.is_a?(Hash) && src["key"].is_a?(String)

        key = src["key"]
        stored_etag = src["etag"]
        path = ctx.resolve(key).path
        current_etag = ctx.file_system.exists?(path) ? ctx.file_system.etag(path) : nil
        suspended = stored_etag && current_etag ? stored_etag != current_etag : false
        result = src.merge("suspended" => suspended)
        child_env = ctx.read(key)
        if child_env
          child_expanded = expand_sources(child_env, ctx, depth: depth + 1)
          child_sources = Array(child_expanded.sources)
          result = result.merge("sources" => child_sources) unless child_sources.empty?
        end
        result
      end

      def key_in_lane?(key, lane_name, ctx)
        mentry = ctx.mentry_for(key)
        mentry && mentry.lane == lane_name
      rescue Textus::Error
        false
      end

      def resolve_blame_path(key, ctx)
        res = ctx.resolve(key)
        res.path || Textus::Protocol::Key::Path.resolve(ctx.manifest.data, res.entry)
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

      def pulse_index_etag(ctx)
        path = ctx.resolve("artifacts.system.index").path
        File.exist?(path) ? ctx.file_system.etag(path) : nil
      rescue Textus::Error
        nil
      end

      def rewrite_data_mv_manifest!(from:, to:, ctx:)
        path = ctx.layout.manifest_path
        raw = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: false)
        raw["lanes"].each { |lane| lane["name"] = to if lane["name"] == from }
        raw["entries"].each do |entry|
          entry["lane"] = to if entry["lane"] == from
          entry["key"] = entry["key"].sub(/\A#{Regexp.escape(from)}(\.|\z)/, "#{to}\\1")
          entry["path"] = entry["path"].sub(%r{\A(data/)?#{Regexp.escape(from)}(/|\z)}, "\\1#{to}\\2")
        end
        File.write(path, YAML.dump(raw))
      end
    end
  end
end
