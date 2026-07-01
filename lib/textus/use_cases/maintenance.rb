# frozen_string_literal: true

require "fileutils"
require "date"
require "digest"
require "yaml"

module Textus
  module UseCases
    module Maintenance
      HANDLES_ALL = [
        Dispatch::Contracts::BootStore,
        Dispatch::Contracts::DoctorStore,
        Dispatch::Contracts::DrainStore,
        Dispatch::Contracts::IngestEntry,
        Dispatch::Contracts::JobsAction,
        Dispatch::Contracts::PublishedEntries,
        Dispatch::Contracts::RuleExplain,
        Dispatch::Contracts::RuleLint,
        Dispatch::Contracts::RuleList,
        Dispatch::Contracts::RuleTrace,
        Dispatch::Contracts::SchemaEnvelope,
      ].freeze
      NEEDS = %i[manifest file_store schemas audit_log layout pipeline job_store workflows].freeze

      def self.call(command, call, deps)
        if command.instance_of?(Dispatch::Contracts::BootStore)
          boot_store(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::DoctorStore)
          doctor_store(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::DrainStore)
          drain_store(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::IngestEntry)
          ingest_entry(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::JobsAction)
          jobs_action(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::PublishedEntries)
          published_entries(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::RuleExplain)
          rule_explain(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::RuleLint)
          rule_lint(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::RuleList)
          rule_list(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::RuleTrace)
          rule_trace(command, call, deps)
        elsif command.instance_of?(Dispatch::Contracts::SchemaEnvelope)
          schema_envelope(command, call, deps)
        else
          raise "Unsupported contract: #{command.class}"
        end
      end

      def self.boot_store(_command, _call, deps)
        proxy = Store::ContainerProxy.new(
          manifest: deps.manifest, file_store: deps.file_store,
          schemas: deps.schemas, audit_log: deps.audit_log,
          layout: deps.layout, pipeline: deps.pipeline,
          job_store: nil, workflows: nil,
          link_edge_store: nil, root: deps.layout.root
        )
        Value::Result.success(Textus::Boot.build(container: proxy))
      end

      def self.doctor_store(command, call, deps)
        proxy = Store::ContainerProxy.new(
          manifest: deps.manifest, file_store: deps.file_store,
          layout: deps.layout, pipeline: deps.pipeline,
          audit_log: deps.audit_log, schemas: deps.schemas,
          job_store: nil, workflows: nil,
          link_edge_store: nil, root: deps.layout.root
        )
        Value::Result.success(Textus::Doctor.build(container: proxy, checks: command.checks, role: call.role))
      end

      def self.drain_store(_command, call, deps)
        proxy = Store::ContainerProxy.new(
          manifest: deps.manifest, file_store: deps.file_store,
          schemas: deps.schemas, audit_log: deps.audit_log,
          job_store: deps.job_store, layout: deps.layout,
          workflows: deps.workflows,
          link_edge_store: nil, pipeline: nil, root: deps.layout.root
        )
        queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
        Textus::Store::Jobs::Planner.seed(container: proxy, queue: queue, role: call.role)
        queue.reclaim(now: Textus::Port::Clock.new.now)
        summary = Textus::Store::Jobs::Worker.for(container: proxy, queue: queue).drain
        Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => summary.failed.zero?,
                              "completed" => summary.completed, "failed" => summary.failed)
      end

      def self.ingest_entry(command, call, deps)
        unless SOURCE_KINDS.include?(command.kind)
          return Value::Result.failure(:usage_error,
                                       "ingest kind must be one of #{SOURCE_KINDS.join("|")}")
        end

        case command.kind
        when "url"   then return Value::Result.failure(:usage_error, "ingest url requires url") unless command.url
        when "file"  then return Value::Result.failure(:usage_error, "ingest file requires path") unless command.path
        when "asset"
          return Value::Result.failure(:usage_error, "ingest asset requires path") unless command.path
          return Value::Result.failure(:usage_error, "ingest asset requires lane") unless command.lane
        end

        now = Time.now.utc
        key = derive_key(now, command.kind, command.slug)
        content_hash = compute_content_hash(command)
        mentry = deps.manifest.resolver.resolve(key).entry
        ts = now.iso8601

        structured = build_structured(ts, now, content_hash, command, deps)
        store = deps.job_store
        index = Textus::Store::Index::Lookup.new(store:)

        duplicate_key = find_duplicate(index, content_hash, command)

        env = if duplicate_key && duplicate_key != key
                supersede_entry(duplicate_key, key, structured, call, deps)
              else
                write_entry(key, structured, mentry, call, deps)
              end

        rebuild_index(store, deps)
        Value::Result.success(env)
      end

      def self.jobs_action(command, _call, deps)
        queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
        case command.action
        when "retry" then queue.retry_failed(command.job_id)
        when "purge" then queue.purge(command.state)
        end
        Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true,
                              "state" => command.state, "jobs" => queue.list(command.state))
      end

      def self.published_entries(_command, _call, deps)
        Value::Result.success(deps.manifest.data.entries.reject { |entry| entry.publish_to.empty? }.map do |entry|
          { "key" => entry.key, "publish_to" => entry.publish_to }
        end)
      end

      def self.rule_explain(command, _call, deps)
        key = command.key
        result = if command.detail
                   explain(key, deps)
                 else
                   effective(key, deps)
                 end
        Value::Result.success(result)
      end

      def self.rule_lint(command, _call, deps)
        root = deps.manifest.data.root
        live_rules = current_rules(root)
        candidate_result = parse_candidate(command.candidate_yaml)
        return candidate_result if candidate_result.is_a?(Value::Result) && candidate_result.failure?

        candidate_rules = candidate_result
        live_by_match = live_rules.to_h { |rule| [rule["match"], rule] }
        candidate_by_match = candidate_rules.to_h { |rule| [rule["match"], rule] }

        steps = (candidate_by_match.keys - live_by_match.keys).map do |match|
          { "op" => "add_rule", "match" => match, "rule" => candidate_by_match[match] }
        end
        (live_by_match.keys - candidate_by_match.keys).each do |match|
          steps << { "op" => "remove_rule", "match" => match }
        end
        (live_by_match.keys & candidate_by_match.keys).each do |match|
          next if live_by_match[match] == candidate_by_match[match]

          steps << { "op" => "change_rule", "match" => match, "from" => live_by_match[match], "to" => candidate_by_match[match] }
        end

        Value::Result.success(Textus::Store::Jobs::Plan.new(steps: steps, warnings: []))
      end

      def self.rule_list(_command, _call, deps)
        Value::Result.success(deps.manifest.rules.blocks.map do |block|
          row = { "match" => block.match }
          LIST_FIELDS.each do |field|
            value = block.public_send(field)
            row[field.to_s] = serialize(field, value) unless value.nil?
          end
          row
        end)
      end

      def self.rule_trace(command, _call, deps)
        _ruleset, trace = deps.manifest.rules.for_with_trace(command.key)
        Value::Result.success({
                                "verb" => "rule_trace",
                                "key" => command.key,
                                "candidates" => trace.candidates,
                                "winners" => trace.winners,
                                "effective" => trace.ruleset_fields,
                              })
      end

      def self.schema_envelope(command, _call, deps)
        mentry = deps.manifest.resolver.resolve(command.key).entry
        schema = deps.schemas.fetch_or_nil(mentry.schema)
        Value::Result.success("protocol" => Textus::PROTOCOL, "key" => command.key,
                              "schema_ref" => mentry.schema, "schema" => schema&.to_h)
      end

      # Ingest Helpers
      SOURCE_KINDS = %w[url file asset].freeze
      CONTENT_HASH_ALGO = "sha256"

      def self.derive_key(now, kind, slug)
        date = now.strftime("%Y.%m.%d")
        "raw.#{date}.#{kind}-#{slug}"
      end

      def self.compute_content_hash(command)
        digest = Digest::SHA256.new
        case command.kind
        when "url" then digest.update(command.url)
        when "file", "asset" then digest.file(command.path)
        end
        "#{CONTENT_HASH_ALGO}:#{digest.hexdigest}"
      end

      def self.build_structured(timestamp, now, content_hash, command, deps)
        base = { "ingested_at" => timestamp, "content_hash" => content_hash }
        case command.kind
        when "url"
          base.merge("source" => { "kind" => "url", "url" => command.url,
                                   "label" => command.label || command.url }, "body" => nil)
        when "file"
          base.merge("source" => { "kind" => "file", "path" => command.path,
                                   "label" => command.label || File.basename(command.path) },
                     "body" => File.read(command.path))
        when "asset"
          asset_rel = copy_asset(now, command.path, command.lane, deps)
          base.merge("source" => { "kind" => "asset",
                                   "label" => command.label || File.basename(command.path) },
                     "asset" => asset_rel, "body" => nil)
        end
      end

      def self.copy_asset(now, path, lane, deps)
        date_path = now.strftime("%Y/%m/%d")
        filename  = File.basename(path)
        assets_dir = deps.layout.asset_raw_dir(date_path, lane)
        FileUtils.mkdir_p(assets_dir)
        FileUtils.cp(path, File.join(assets_dir, filename))
        sentinel = deps.layout.asset_sentinel_path
        File.write(sentinel, "*\n") unless File.exist?(sentinel)
        "raw/#{date_path}/#{lane}/#{filename}"
      end

      def self.write_entry(key, structured, mentry, call, deps)
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: reader, layout: deps.layout
        )
        writer.put(key, mentry: mentry,
                        payload: Textus::Value::Payload.new(meta: nil, body: nil, content: structured))
      end

      def self.find_duplicate(index, content_hash, command)
        dup = index.find_by_hash(content_hash)
        return dup if dup
        return unless command.kind == "url"

        index.find_by_url(command.url)
      end

      def self.supersede_entry(old_key, new_key, structured, call, deps)
        old_mentry = deps.manifest.resolver.resolve(old_key).entry
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        old_env = reader.read(old_key)
        old_content = old_env&.content || {}
        tombstone = {}
        %w[ingested_at].each { |k| tombstone[k] = old_content[k] if old_content.key?(k) }
        source_kind = old_content.dig("source", "kind")
        tombstone["source"] = { "kind" => source_kind } if source_kind
        tombstone["superseded_by"] = new_key

        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: reader, layout: deps.layout
        )
        writer.put(old_key, mentry: old_mentry,
                            payload: Textus::Value::Payload.new(meta: nil, body: nil, content: tombstone))

        structured["supersedes"] = old_key
        env = write_entry(new_key, structured,
                          deps.manifest.resolver.resolve(new_key).entry, call, deps)

        move_asset(old_content["asset"], command.lane, deps) if command.kind == "asset" && old_content["asset"]

        rebuild_index(deps.job_store, deps)
        env
      end

      def self.move_asset(old_rel, lane, deps)
        old_path = deps.layout.asset_resolve(old_rel)
        return unless File.exist?(old_path)

        now = Time.now.utc
        date_path = now.strftime("%Y/%m/%d")
        filename = File.basename(old_path)
        new_dir = deps.layout.asset_raw_dir(date_path, lane)
        new_path = File.join(new_dir, filename)
        return if old_path == new_path

        FileUtils.mkdir_p(new_dir)
        FileUtils.mv(old_path, new_path)
      rescue Errno::ENOENT, Errno::EACCES => e
        warn "[textus ingest] could not move asset #{old_rel}: #{e.message}"
      end

      def self.rebuild_index(store, deps)
        Textus::Store::Index::Builder.new(store:).rebuild!(resolver: deps.manifest.resolver)
      end

      # RuleExplain Helpers
      LEAN_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY
                    .select { |_, m| m[:in_rule_explain].include?(:lean) }.keys.freeze
      DETAIL_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY
                      .select { |_, m| m[:in_rule_explain].include?(:detail) }.keys.freeze
      EFFECTIVE_FIELDS = DETAIL_FIELDS.select { |f| Textus::Manifest::Schema::FIELD_REGISTRY[f][:policy_class] }.freeze

      def self.effective(key, deps)
        set = deps.manifest.rules.for(key)
        LEAN_FIELDS.each_with_object({}) do |field, out|
          value = set.public_send(field)
          out[field.to_s] = lean_value(field, value) unless value.nil?
        end
      end

      def self.lean_value(field, value)
        case field
        when :retention then retention_hash(value, string_keys: true)
        when :react then value.to_h
        else value
        end
      end

      def self.explain(key, deps)
        matching = deps.manifest.rules.explain(key)
        winners = deps.manifest.rules.for(key)
        {
          key: key,
          matched_blocks: matching.map do |block|
            { match: block.match }.merge(DETAIL_FIELDS.to_h { |f| [f, !block.public_send(f).nil?] })
          end,
          effective: EFFECTIVE_FIELDS.to_h { |f| [f, effective_value(f, winners.public_send(f))] },
          guards: Textus::Manifest::Policy::Predicates::FLOOR.keys.to_h do |action|
            floor = Textus::Manifest::Policy::Predicates::FLOOR.fetch(action, [])
            rule = Array(deps.manifest.rules.for(key).guard&.dig(action.to_s))
            [action, { floor: floor, rule: rule }]
          end,
        }
      end

      def self.effective_value(field, value)
        return nil if value.nil?

        case field
        when :retention then retention_hash(value, string_keys: false)
        when :react then value.to_h
        else value
        end
      end

      def self.retention_hash(retention, string_keys:)
        h = { ttl_seconds: retention.ttl_seconds, action: retention.action }
        string_keys ? h.transform_keys(&:to_s) : h
      end

      # RuleLint Helpers
      def self.current_rules(root)
        raw = YAML.safe_load_file(File.join(root, "manifest.yaml"), permitted_classes: [Symbol], aliases: false)
        Array(raw["rules"])
      end

      def self.parse_candidate(yaml_text)
        raw = YAML.safe_load(yaml_text, permitted_classes: [Symbol], aliases: false)
        return Value::Result.failure(:usage_error, "candidate is not a YAML mapping") unless raw.is_a?(Hash)

        Array(raw["rules"])
      rescue Psych::Exception => e
        Value::Result.failure(:usage_error, "candidate YAML parse error: #{e.message}")
      end

      # RuleList Helpers
      LIST_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY.select { |_, m| m[:in_rule_list] }.keys.freeze

      def self.serialize(field, value)
        case field
        when :retention then { "ttl_seconds" => value.ttl_seconds, "action" => value.action.to_s }
        when :react then value.to_h
        else value
        end
      end
    end
  end
end
