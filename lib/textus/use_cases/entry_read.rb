module Textus
  module UseCases
    module EntryRead
      HANDLES_ALL = [
        Dispatch::Contracts::GetEntry,
        Dispatch::Contracts::UidEntry,
        Dispatch::Contracts::WhereEntry,
        Dispatch::Contracts::AuditEntries,
        Dispatch::Contracts::BlameEntry,
        Dispatch::Contracts::DepsEntry,
        Dispatch::Contracts::RdepsEntry,
        Dispatch::Contracts::GraphEntry,
        Dispatch::Contracts::DiffEntry,
        Dispatch::Contracts::ListKeys,
        Dispatch::Contracts::PulseEntries,
      ].freeze
      NEEDS = %i[file_store manifest layout freshness_evaluator audit_log job_store link_edge_store].freeze

      def self.call(command, call, deps)
        if command.instance_of?(Dispatch::Contracts::GetEntry)
          get_entry(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::UidEntry)
          uid_entry(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::WhereEntry)
          where_entry(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::AuditEntries)
          audit_entries(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::BlameEntry)
          blame_entry(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::DepsEntry)
          deps_entry(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::RdepsEntry)
          rdeps_entry(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::GraphEntry)
          graph_entry(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::DiffEntry)
          diff_entry(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::ListKeys)
          list_keys(command, deps)
        elsif command.instance_of?(Dispatch::Contracts::PulseEntries)
          pulse_entries(command, call, deps)
        else
          raise "Unsupported contract: #{command.class} (ID: #{command.class.object_id})"
        end
      end

      def self.get_entry(command, deps)
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        envelope = reader.read(command.key)
        return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

        envelope = expand_sources(envelope, depth: 0, deps: deps)
        Value::Result.success(envelope.with(freshness: deps.freshness_evaluator.verdict(resolve_entry(command.key, deps: deps))))
      end

      def self.uid_entry(command, deps)
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        envelope = reader.read(command.key)
        return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

        Value::Result.success(envelope.uid)
      end

      def self.where_entry(command, deps)
        res = deps.manifest.resolver.resolve(command.key)
        mentry = res.entry
        Value::Result.success("protocol" => Textus::PROTOCOL, "key" => command.key,
                              "lane" => mentry.lane, "owner" => mentry.owner, "path" => res.path)
      end

      def self.audit_entries(command, deps)
        cursor_check = check_cursor_expiry(command.seq_since, deps)
        return cursor_check if cursor_check

        rows = deps.audit_log.scan(
          seq_since: command.seq_since,
          key: command.key, role: command.role, verb: command.verb,
          correlation_id: command.correlation_id, limit: command.limit
        ).select do |row|
          next false if command.lane && !key_in_lane?(row["key"], command.lane, deps)
          next false if command.since && (row["ts"].nil? || Time.parse(row["ts"]) < command.since)

          true
        end
        Value::Result.success(rows)
      end

      def self.blame_entry(command, call, deps)
        root = deps.manifest.data.root
        audit = audit_entries(
          Data.define(:seq_since, :key, :lane, :role, :verb, :since, :correlation_id, :limit).new(
            seq_since: nil, key: command.key, lane: nil, role: call.role, verb: nil, since: nil, correlation_id: nil, limit: nil,
          ),
          deps,
        )
        return audit if audit.failure?

        audit_rows = audit.value || []

        path = resolve_path(command.key, deps)
        return Value::Result.success(audit_rows.map { |row| row.merge("git" => nil) }) unless git_tracked?(path, root: root)

        Value::Result.success(audit_rows.map { |row| row.merge("git" => git_commit_at(path, timestamp: row["ts"], root: root)) })
      end

      def self.deps_entry(command, deps)
        entry = deps.manifest.data.entries.find { |e| e.key == command.key }
        deps_list = entry&.external? ? Array(entry.source&.sources).compact : []
        Value::Result.success("key" => command.key, "deps" => deps_list.uniq)
      end

      def self.rdeps_entry(command, deps)
        source_rdeps = deps.manifest.data.entries.each_with_object([]) do |entry, acc|
          next unless entry.external?

          sources = Array(entry.source&.sources).compact
          acc << entry.key if sources.any? { |s| s == command.key || command.key.start_with?("#{s}.") }
        end

        link_rdeps = deps.link_edge_store.dependents_of(command.key)
        rdeps      = (source_rdeps + link_rdeps).uniq.sort
        Value::Result.success("key" => command.key, "rdeps" => rdeps)
      end

      def self.graph_entry(command, deps)
        neighbors  = deps.link_edge_store.neighbors_of(command.key)
        reachable  = deps.link_edge_store.reachable(command.key, depth: command.depth)
        Value::Result.success(
          "key" => command.key,
          "neighbors" => neighbors.sort,
          "reachable" => reachable.sort,
        )
      end

      def self.diff_entry(command, deps)
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        proposal_env = reader.read(command.pending_key)
        target_key = proposal_target_key(proposal_env, command.pending_key)
        return target_key if target_key.is_a?(Value::Result)

        target_env = reader.read(target_key)

        body_diff = Textus::Diff.body(target_env&.body, proposal_env.body)
        meta_diff = Textus::Diff.meta(target_env&.meta&.dig("_meta") || {}, proposal_env.meta&.dig("_meta") || {})

        target_schema = target_schema_ref(target_key, deps)
        proposal_schema = proposal_env&.meta&.dig("_meta", "schema")
        schema_diff = diff_schema(target_schema, proposal_schema)

        result = { "pending_key" => command.pending_key, "target_key" => target_key }
        result["body"] = body_diff if body_diff
        result["meta"] = meta_diff if meta_diff
        result["schema"] = schema_diff if schema_diff
        result["summary"] = Textus::Diff.summary(result)

        Value::Result.success(result)
      end

      def self.proposal_target_key(proposal_env, pending_key)
        proposal = proposal_env&.meta&.dig("proposal")
        return Value::Result.failure(:proposal_error, "entry has no proposal block: #{pending_key}") unless proposal

        target_key = proposal["target_key"]
        return Value::Result.failure(:proposal_error, "proposal missing target_key") unless target_key

        target_key
      end

      def self.diff_schema(target_schema, proposal_schema)
        return nil unless proposal_schema && target_schema != proposal_schema

        Textus::Diff.schema({ "schema" => target_schema }, { "schema" => proposal_schema })
      end

      def self.target_schema_ref(key, deps)
        entry = deps.manifest.data.entries.find { |e| e.key == key }
        entry&.schema_ref
      end

      def self.list_keys(command, deps)
        q      = command.respond_to?(:q)      ? command.q      : nil
        schema = command.respond_to?(:schema) ? command.schema : nil

        if deps.job_store && (q || schema)
          return sqlite_list(query: q, schema: schema, lane: command.lane, prefix: command.prefix,
                             deps: deps)
        end

        manifest_list(prefix: command.prefix, lane: command.lane, deps: deps)
      end

      def self.sqlite_list(query:, schema:, lane:, prefix:, deps:)
        rows = deps.job_store.search_entries(q: query, schema: schema, lane: lane, prefix: prefix)
        Value::Result.success((rows || []).map { |r| { "key" => r["key"], "lane" => r["lane"] } })
      end

      def self.manifest_list(prefix:, lane:, deps:)
        rows = deps.manifest.resolver.enumerate(prefix: prefix)
        rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
        Value::Result.success(rows.map do |row|
          { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] }
        end)
      end

      def self.pulse_entries(command, call, deps)
        root  = deps.manifest.data.root
        since = command.since || Textus::Store::Cursor.new(root: root, role: call.role).read

        changed = changed_since(since, call, deps)

        result = {
          "cursor" => deps.audit_log.latest_seq,
          "changed" => changed,
          "pending_review" => review_keys(call, deps),
          "contract_etag" => Textus::Value::Etag.for_contract(root),
          "index_etag" => index_etag(deps),
        }

        Textus::Store::Cursor.new(root: root, role: call.role).write(result["cursor"])
        Value::Result.success(result)
      end

      def self.changed_since(since, _call, deps)
        if deps.job_store
          sqlite_rows = deps.job_store.audit_events_since(seq: since)
          return sqlite_rows.map { |r| { "key" => r["key"], "verb" => r["verb"], "seq" => r["seq"] } } if sqlite_rows.any?
        end

        audit = audit_entries(
          Data.define(:seq_since, :key, :lane, :role, :verb, :since, :correlation_id, :limit).new(
            seq_since: since, key: nil, lane: nil, role: nil, verb: nil, since: nil, correlation_id: nil, limit: nil,
          ),
          deps,
        )
        return [] if audit.failure?

        audit.value || []
      end

      def self.review_keys(_call, deps)
        queue = deps.manifest.policy.queue_lane
        return [] unless queue

        result = list_keys(
          Data.define(:prefix, :lane, :q, :schema).new(
            prefix: nil, lane: queue, q: nil, schema: nil,
          ),
          deps,
        )
        return [] unless result.success?

        result.value.map { |r| r["key"] }
      end

      def self.index_etag(deps)
        path = deps.manifest.resolver.resolve("artifacts.system.index").path
        File.exist?(path) ? deps.file_store.etag(path) : nil
      rescue Textus::Error
        nil
      end

      def self.expand_sources(envelope, depth:, deps:)
        return envelope if depth >= 5 # MAX_SOURCE_DEPTH

        raw_sources = Array(envelope.meta["sources"])
        return envelope if raw_sources.empty?

        expanded = raw_sources.map { |src| expand_one_source(src, depth: depth, deps: deps) }
        envelope.with(sources: expanded)
      end

      def self.expand_one_source(src, depth:, deps:)
        src = { "key" => src } if src.is_a?(String)
        return src unless src.is_a?(Hash) && src["key"].is_a?(String)

        key = src["key"]
        stored_etag = src["etag"]
        current_etag = resolve_current_etag(key, deps: deps)
        suspended = stored_etag && current_etag ? stored_etag != current_etag : false

        result = src.merge("suspended" => suspended)

        child_env = resolve_env(key, deps: deps)
        if child_env
          child_expanded = expand_sources(child_env, depth: depth + 1, deps: deps)
          child_sources = Array(child_expanded.sources)
          result = result.merge("sources" => child_sources) unless child_sources.empty?
        end

        result
      end

      def self.resolve_current_etag(key, deps:)
        path = deps.manifest.resolver.resolve(key).path
        return nil unless deps.file_store.exists?(path)

        deps.file_store.etag(path)
      rescue Textus::Error
        nil
      end

      def self.resolve_entry(key, deps:)
        deps.manifest.resolver.resolve(key).entry
      end

      def self.resolve_env(key, deps:)
        Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout).read(key)
      end

      def self.check_cursor_expiry(seq_since, deps)
        return unless seq_since

        min = deps.audit_log.min_available_seq
        return unless min && seq_since < min - 1

        Value::Result.failure(:cursor_expired, "requested seq #{seq_since} is below minimum available #{min}",
                              details: { requested: seq_since, min_available: min })
      end

      def self.key_in_lane?(key, lane, deps)
        mentry = deps.manifest.resolver.resolve(key).entry
        mentry && mentry.lane == lane
      rescue Textus::Error
        false
      end

      def self.resolve_path(key, deps)
        res = deps.manifest.resolver.resolve(key)
        path = res.path
        path || Textus::Key::Path.resolve(deps.manifest.data, res.entry)
      rescue Textus::Error
        nil
      end

      def self.git_tracked?(path, root:)
        return false if path.nil? || !File.exist?(path) || !git_repo?(root)

        _out, _err, status = Open3.capture3("git", "ls-files", "--error-unmatch", path, chdir: root)
        status.success?
      rescue Errno::ENOENT
        false
      end

      def self.git_repo?(root)
        dir = root
        loop do
          return true if File.directory?(File.join(dir, ".git"))

          parent = File.dirname(dir)
          return false if parent == dir

          dir = parent
        end
      end

      def self.git_commit_at(path, timestamp:, root:)
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
    end
  end
end
