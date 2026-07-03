module Textus
  module Protocol
    class Gate
      module Builtin
        CONTAINER_ERROR = ->(msg) { { error: { code: "not_found", message: msg } } }
        USAGE_ERROR     = ->(msg) { { error: { code: "usage_error", message: msg } } }

        private

        def container = @pipeline.container
        def reader = container.reader
        def writer = container.writer
        def manifest = container.manifest
        def entry_index = container.entry_index
        def schemas = container.schemas
        def audit_log = container.audit_log
        def file_system = container.file_system
        def link_graph = container.link_graph
        def event_store = container.event_store
        def workflows = container.workflows
        def layout = container.layout

        public

        def builtin_get(key:, call:)
          env = reader.read(key)
          return CONTAINER_ERROR.call("no entry at #{key}") unless env

          expand_sources(env, depth: 0)
        end

        def builtin_put(key:, meta: nil, body: nil, content: nil, if_etag: nil, call:)
          env = writer.put(key,
            mentry: manifest.resolver.resolve(key).entry,
            payload: Textus::Value::Payload.new(meta: meta || {}, body:, content:),
            if_etag:, call:)
          { "uid" => env.uid, "etag" => env.etag }
        end

        def builtin_list(prefix: nil, lane: nil, q: nil, schema: nil, call:)
          if entry_index && (q || schema)
            rows = entry_index.search(query: q, schema:, lane:, prefix:)
            (rows || []).map { |r| { "key" => r["key"], "lane" => r["lane"] } }
          else
            rows = manifest.resolver.enumerate(prefix:)
            rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
            rows.map { |row| { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] } }
          end
        end

        def builtin_delete(key:, if_etag: nil, call:)
          writer.delete(key, if_etag:, call:)
          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
        end
        alias builtin_key_delete builtin_delete

        def builtin_where(key:, call:)
          res = manifest.resolver.resolve(key)
          { "protocol" => Textus::PROTOCOL, "key" => key, "lane" => res.entry.lane, "path" => res.path }
        end

        def builtin_uid(key:, call:)
          env = reader.read(key)
          return CONTAINER_ERROR.call("no entry at #{key}") unless env

          env.uid
        end

        def builtin_move(old_key:, new_key:, if_etag: nil, dry_run: false, call:)
          Textus::Protocol::Manifest::Data.validate_key!(old_key)
          Textus::Protocol::Manifest::Data.validate_key!(new_key)
          return USAGE_ERROR.call("old and new keys are identical") if old_key == new_key

          old_res = manifest.resolver.resolve(old_key)
          new_res = manifest.resolver.resolve(new_key)

          return USAGE_ERROR.call("source key '#{old_key}' not found") unless reader.exists?(old_key)
          return USAGE_ERROR.call("target '#{new_key}' already exists") if reader.exists?(new_key)
          return USAGE_ERROR.call("cross-zone moves forbidden (#{old_res.entry.lane} \u2192 #{new_res.entry.lane})") unless old_res.entry.lane == new_res.entry.lane

          pre_env = reader.read(old_key)
          writer.put(old_key, mentry: old_res.entry, call:,
                     payload: Textus::Value::Payload.new(meta: pre_env.meta, body: pre_env.body, content: pre_env.content)) unless pre_env.uid

          if dry_run
            return { "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => true,
                     "from_key" => old_key, "to_key" => new_key,
                     "from_path" => old_res.path, "to_path" => new_res.path, "uid" => pre_env.uid }
          end

          envelope = writer.move(from_key: old_key, to_key: new_key, new_mentry: new_res.entry, call:)
          { "protocol" => Textus::PROTOCOL, "ok" => true, "from_key" => old_key, "to_key" => new_key,
            "from_path" => old_res.path, "to_path" => new_res.path, "uid" => envelope.uid, "envelope" => envelope.to_h_for_wire }
        end

        def builtin_deps(key:, call:)
          entry = manifest.data.entries.find { |e| e.key == key }
          deps_list = entry&.external? ? Array(entry.source&.sources).compact : []
          { "key" => key, "deps" => deps_list.uniq }
        end

        def builtin_rdeps(key:, call:)
          source_rdeps = manifest.data.entries.each_with_object([]) do |entry, acc|
            next unless entry.external?
            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
          end
          link_rdeps = link_graph.links_to(key)
          { "key" => key, "rdeps" => (source_rdeps + link_rdeps).uniq.sort }
        end

        def builtin_graph(key:, depth: nil, call:)
          from = link_graph.links_from(key)
          to   = link_graph.links_to(key)
          { "key" => key, "neighbors" => (from + to).uniq.sort,
            "reachable" => link_graph.reachable(from: key, depth:).sort }
        end

        def builtin_boot(call:)
          storage    = Textus::Infra::Store::Container::Storage.new(
            file_system:, entry_store: nil, layout:, entry_index: nil)
          events     = Textus::Infra::Store::Container::Events.new(event_store: nil, workflows: nil)
          governance = Textus::Infra::Store::Container::Governance.new(manifest:, schemas:)
          logging    = Textus::Infra::Store::Container::Logging.new(audit_log:)
          links      = Textus::Infra::Store::Container::Links.new(link_graph: nil)
          proxy = Textus::Infra::Store::Container.new(
            storage:, events:, governance:, logging:, links:,
            root: layout.root, pipeline:)
          Textus::Protocol::Boot.build(container: proxy)
        end

        def builtin_schema_show(key:, call:)
          mentry = manifest.resolver.resolve(key).entry
          schema = schemas.fetch_or_nil(mentry.schema)
          { "protocol" => Textus::PROTOCOL, "key" => key,
            "schema_ref" => mentry.schema, "schema" => schema&.to_h }
        end

        def builtin_published(call:)
          manifest.data.entries.reject { |entry| entry.publish_to.empty? }.map do |entry|
            { "key" => entry.key, "publish_to" => entry.publish_to }
          end
        end

        def builtin_audit(key: nil, lane: nil, role: nil, verb: nil, since: nil, seq_since: nil, correlation_id: nil, limit: nil, call:)
          if seq_since
            min = audit_log.min_available_seq
            raise Textus::CursorExpired.new(requested: seq_since, min_available: min) if min && seq_since < min - 1
          end
          rows = audit_log.scan(seq_since:, key:, role:, verb:, correlation_id:, limit:).select do |row|
            next false if lane && !key_in_lane?(row["key"], lane)
            next false if since && row["ts"] && Time.parse(row["ts"]) < since
            true
          end
          { "verb" => "audit", "rows" => rows }
        end

        def builtin_blame(key:, limit: nil, call:)
          audit_result = builtin_audit(key:, call:)
          audit_rows = audit_result["rows"] || []
          root = manifest.data.root
          path = resolve_blame_path(key)
          return audit_rows.map { |row| row.merge("git" => nil) } unless git_tracked?(path, root:)

          audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"], root:)) }
        end

        def builtin_pulse(since: nil, call:)
          root = manifest.data.root
          cursor_val = since || Textus::Protocol::Cursor.new(root:, role: call.role).read
          audit_result = builtin_audit(seq_since: cursor_val, call:)
          changed = audit_result["rows"] || []
          queue = manifest.policy.queue_lane
          pending = queue ? builtin_list(lane: queue, call:) : []
          result = {
            "cursor" => audit_log.latest_seq,
            "changed" => changed,
            "pending_review" => pending.is_a?(Array) ? pending.map { |r| r["key"] } : [],
            "contract_etag" => Textus::Value::Etag.for_contract(root),
            "index_etag" => pulse_index_etag,
          }
          Textus::Protocol::Cursor.new(root:, role: call.role).write(result["cursor"])
          result
        end

        def builtin_drain(prefix: nil, lane: nil, call:)
          registry = Textus::Workflow::Registry.new(workflows)
          result = Textus::Protocol::Events::Consumer.new.drain(
            event_store:, registry:, container: @pipeline.container, call:)
          { "protocol" => Textus::PROTOCOL, "ok" => result[:failed].zero?,
            "completed" => result[:completed], "failed" => result[:failed] }
        end

        def builtin_key_mv_prefix(from_prefix:, to_prefix:, dry_run: false, call:)
          return USAGE_ERROR.call("from_prefix and to_prefix required") unless from_prefix && to_prefix
          leaves = builtin_list(prefix: from_prefix, call:)
          return leaves if leaves.is_a?(Hash) && leaves[:error]
          return USAGE_ERROR.call("from_prefix is a leaf \u2014 use mv") if leaves.any? { |r| r["key"] == from_prefix }

          warnings = leaves.empty? ? ["no keys under #{from_prefix}"] : []
          steps = leaves.map do |row|
            tail = row["key"].delete_prefix("#{from_prefix}.")
            { "op" => "mv", "from" => row["key"], "to" => "#{to_prefix}.#{tail}" }
          end
          plan = Textus::Infra::Store::Retention::Plan.new(steps:, warnings:)
          return plan.to_h if dry_run
          steps.each { |s| builtin_move(old_key: s["from"], new_key: s["to"], call:) }
          plan.to_h
        end

        def builtin_key_delete_prefix(prefix:, dry_run: false, call:)
          return USAGE_ERROR.call("prefix required") unless prefix && !prefix.empty?
          leaves = builtin_list(prefix:, call:)
          return leaves if leaves.is_a?(Hash) && leaves[:error]

          warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
          steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }
          plan = Textus::Infra::Store::Retention::Plan.new(steps:, warnings:)
          return plan.to_h if dry_run
          steps.each { |s| builtin_delete(key: s["key"], call:) }
          plan.to_h
        end

        def builtin_data_mv(from:, to:, dry_run: false, call:)
          return USAGE_ERROR.call("from and to required") unless from && to
          return USAGE_ERROR.call("data lane '#{from}' not declared") unless manifest.data.declared_lane_kinds.key?(from)

          dest_dir = layout.lane_path(to)
          return USAGE_ERROR.call("destination data/#{to} already exists") if File.exist?(dest_dir)

          affected_keys = manifest.data.entries.select { |e| e.lane == from }.map(&:key)
          steps = [{ "op" => "rename_zone", "from" => from, "to" => to }]
          steps += affected_keys.map { |k| { "op" => "mv", "from" => k, "to" => "#{to}#{k[from.length..]}" } }
          plan = Textus::Infra::Store::Retention::Plan.new(steps:, warnings: [])
          return plan.to_h if dry_run

          rewrite_data_mv_manifest!(from:, to:)
          FileUtils.mv(layout.lane_path(from), dest_dir)
          plan.to_h
        end

        private

        def expand_sources(envelope, depth:)
          return envelope if depth >= 5
          raw_sources = Array(envelope.meta["sources"])
          return envelope if raw_sources.empty?
          expanded = raw_sources.map { |src| expand_one_source(src, depth:) }
          envelope.with(sources: expanded)
        end

        def expand_one_source(src, depth:)
          src = { "key" => src } if src.is_a?(String)
          return src unless src.is_a?(Hash) && src["key"].is_a?(String)
          key = src["key"]
          stored_etag = src["etag"]
          path = manifest.resolver.resolve(key).path
          current_etag = file_system.exists?(path) ? file_system.etag(path) : nil
          suspended = stored_etag && current_etag ? stored_etag != current_etag : false
          result = src.merge("suspended" => suspended)
          child_env = reader.read(key)
          if child_env
            child_expanded = expand_sources(child_env, depth: depth + 1)
            child_sources = Array(child_expanded.sources)
            result = result.merge("sources" => child_sources) unless child_sources.empty?
          end
          result
        end

        def key_in_lane?(key, lane_name)
          mentry = manifest.resolver.resolve(key).entry
          mentry && mentry.lane == lane_name
        rescue Textus::Error
          false
        end

        def resolve_blame_path(key)
          res = manifest.resolver.resolve(key)
          res.path || Textus::Protocol::Key::Path.resolve(manifest.data, res.entry)
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

        def pulse_index_etag
          path = manifest.resolver.resolve("artifacts.system.index").path
          File.exist?(path) ? file_system.etag(path) : nil
        rescue Textus::Error
          nil
        end

        def rewrite_data_mv_manifest!(from:, to:)
          path = layout.manifest_path
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
end
