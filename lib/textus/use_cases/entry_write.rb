module Textus
  module UseCases
    module EntryWrite
      HANDLES_ALL = [
        Dispatch::Contracts::PutEntry,
        Dispatch::Contracts::MoveKey,
        Dispatch::Contracts::DeleteKey,
        Dispatch::Contracts::KeyMvPrefix,
        Dispatch::Contracts::KeyDeletePrefix,
        Dispatch::Contracts::ProposeEntry,
        Dispatch::Contracts::AcceptProposal,
        Dispatch::Contracts::RejectProposal,
        Dispatch::Contracts::EnqueueJob,
        Dispatch::Contracts::DataMv,
      ].freeze
      NEEDS = %i[file_store manifest schemas audit_log layout event_bus job_store].freeze

      DISPATCH = {
        Dispatch::Contracts::PutEntry => :put_entry,
        Dispatch::Contracts::MoveKey => :move_key,
        Dispatch::Contracts::DeleteKey => :delete_key,
        Dispatch::Contracts::KeyMvPrefix => :key_mv_prefix,
        Dispatch::Contracts::KeyDeletePrefix => :key_delete_prefix,
        Dispatch::Contracts::ProposeEntry => :propose_entry,
        Dispatch::Contracts::AcceptProposal => :accept_proposal,
        Dispatch::Contracts::RejectProposal => :reject_proposal,
        Dispatch::Contracts::EnqueueJob => :enqueue_job,
        Dispatch::Contracts::DataMv => :data_mv,
      }.freeze

      def self.call(command, call, deps)
        method = DISPATCH[command.class]
        raise "Unsupported contract: #{command.class}" unless method

        send(method, command, call, deps)
      end

      def self.put_entry(command, call, deps)
        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout), layout: deps.layout
        )
        envelope = writer.put(
          command.key,
          mentry: deps.manifest.resolver.resolve(command.key).entry,
          payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content),
          if_etag: command.if_etag,
        )
        Value::Result.success(envelope)
      end

      def self.move_key(command, call, deps)
        Textus::Manifest::Data.validate_key!(command.old_key)
        Textus::Manifest::Data.validate_key!(command.new_key)

        return Value::Result.failure(:usage_error, "mv: old and new keys are identical") if command.old_key == command.new_key

        old_res = deps.manifest.resolver.resolve(command.old_key)
        new_res = deps.manifest.resolver.resolve(command.new_key)

        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)

        unless reader.exists?(command.old_key)
          return Value::Result.failure(:not_found,
                                       "source key '#{command.old_key}' not found")
        end

        zone_check = validate_zone(old_res.entry, new_res.entry)
        return zone_check if zone_check

        if reader.exists?(command.new_key)
          return Value::Result.failure(:usage_error, "mv: target '#{command.new_key}' already exists at #{new_res.path}")
        end

        pre_env = reader.read(command.old_key)
        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: reader, layout: deps.layout
        )
        unless pre_env.uid
          writer.put(
            command.old_key, mentry: old_res.entry,
                             payload: Textus::Value::Payload.new(meta: pre_env.meta, body: pre_env.body, content: pre_env.content)
          )
        end

        if command.dry_run
          return Value::Result.success({
                                         "protocol" => Textus::PROTOCOL, "ok" => true, "dry_run" => true,
                                         "from_key" => command.old_key, "to_key" => command.new_key,
                                         "from_path" => old_res.path, "to_path" => new_res.path,
                                         "uid" => pre_env.uid
                                       })
        end

        envelope = writer.move(
          from_key: command.old_key, to_key: command.new_key,
          new_mentry: new_res.entry
        )

        Value::Result.success({
                                "protocol" => Textus::PROTOCOL, "ok" => true,
                                "from_key" => command.old_key, "to_key" => command.new_key,
                                "from_path" => old_res.path, "to_path" => new_res.path,
                                "uid" => envelope.uid, "envelope" => envelope.to_h_for_wire
                              })
      end

      def self.validate_zone(old_entry, new_entry)
        return nil if old_entry.lane == new_entry.lane

        Value::Result.failure(:usage_error,
                              "mv: cross-zone moves are forbidden (from #{old_entry.lane} to #{new_entry.lane})")
      end

      def self.delete_key(command, call, deps)
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: reader, layout: deps.layout
        )
        writer.delete(command.key, if_etag: command.if_etag)
        if deps.respond_to?(:event_bus) && deps.event_bus
          deps.event_bus.emit(Textus::Event::EntryDeleted.new(
                                key: command.key,
                                role: call.role,
                                etag_before: nil,
                                occurred_at: call.now,
                              ))
        end
        Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "key" => command.key, "deleted" => true)
      end

      def self.key_mv_prefix(command, call, deps)
        if command.from_prefix.nil? || command.to_prefix.nil?
          return Value::Result.failure(:usage_error,
                                       "from_prefix and to_prefix required")
        end

        list = UseCases::EntryRead.list_keys(
          Data.define(:prefix, :lane, :q, :schema).new(
            prefix: command.from_prefix, lane: nil, q: nil, schema: nil,
          ),
          deps,
        )
        return list if list.failure?

        leaves = list.value || []

        if leaves.any? { |r| r["key"] == command.from_prefix }
          return Value::Result.failure(:usage_error,
                                       "from_prefix '#{command.from_prefix}' is itself a leaf — use `mv` to rename a single key")
        end

        warnings = leaves.empty? ? ["no keys under #{command.from_prefix}"] : []
        steps = leaves.map do |row|
          old_key = row["key"]
          tail = old_key.delete_prefix("#{command.from_prefix}.")
          new_key = "#{command.to_prefix}.#{tail}"
          { "op" => "mv", "from" => old_key, "to" => new_key }
        end

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
        return Value::Result.success(plan) if command.dry_run

        steps.each do |step|
          move = move_key(
            Data.define(:old_key, :new_key, :if_etag, :dry_run).new(
              old_key: step["from"], new_key: step["to"], if_etag: nil, dry_run: false,
            ),
            call,
            deps,
          )
          return move if move.failure?
        end
        Value::Result.success(plan)
      end

      def self.key_delete_prefix(command, call, deps)
        return Value::Result.failure(:usage_error, "prefix required") if command.prefix.nil? || command.prefix.empty?

        list = UseCases::EntryRead.list_keys(
          Data.define(:prefix, :lane, :q, :schema).new(
            prefix: command.prefix, lane: nil, q: nil, schema: nil,
          ),
          deps,
        )
        return list if list.failure?

        leaves = list.value || []

        warnings = leaves.empty? ? ["no keys under #{command.prefix}"] : []
        steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
        return Value::Result.success(plan) if command.dry_run

        steps.each do |step|
          delete = delete_key(
            Data.define(:key, :if_etag).new(
              key: step["key"], if_etag: nil,
            ),
            call,
            deps,
          )
          return delete if delete.failure?
        end
        Value::Result.success(plan)
      end

      def self.propose_entry(command, call, deps)
        zone = deps.manifest.policy.propose_lane_for(call.role)
        unless zone
          return Value::Result.failure(:propose_forbidden,
                                       "role '#{call.role}' has no writable propose_lane",
                                       details: { "role" => call.role })
        end

        key = "#{zone}.#{command.key}"
        mentry = deps.manifest.resolver.resolve(key).entry
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: reader, layout: deps.layout
        )
        envelope = writer.put(
          key, mentry: mentry,
               payload: Textus::Value::Payload.new(meta: command.meta || {}, body: command.body, content: command.content)
        )
        if deps.respond_to?(:event_bus) && deps.event_bus
          deps.event_bus.emit(Textus::Event::EntryWritten.new(
                                key: key,
                                role: call.role,
                                etag_before: nil,
                                etag_after: envelope.etag,
                                occurred_at: call.now,
                              ))
        end
        Value::Result.success(envelope)
      end

      def self.accept_proposal(command, call, deps)
        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        env = reader.read(command.pending_key)
        proposal = env&.meta&.dig("proposal") or
          return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
        target = proposal["target_key"] or
          return Value::Result.failure(:proposal_error, "proposal missing target_key")
        action = proposal["action"] || "put"

        if command.dry_run
          target_env = reader.read(target)
          body_diff = Textus::Diff.body(target_env&.body, env.body)
          meta_diff = Textus::Diff.meta(target_env&.meta&.dig("_meta") || {}, env.meta&.dig("_meta") || {})
          result = { "dry_run" => true, "pending_key" => command.pending_key, "target_key" => target, "action" => action }
          result["body"] = body_diff if body_diff
          result["meta"] = meta_diff if meta_diff
          result["summary"] = Textus::Diff.summary(result)
          return Value::Result.success(result)
        end

        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: reader, layout: deps.layout
        )
        case action
        when "put"
          mentry = deps.manifest.resolver.resolve(target).entry
          writer.put(
            target, mentry: mentry,
                    payload: Textus::Value::Payload.new(meta: env.meta["_meta"] || {}, body: env.body, content: nil)
          )
        when "delete"
          writer.delete(target)
        else
          return Value::Result.failure(:proposal_error, "unknown action: #{action}")
        end

        writer.delete(command.pending_key)
        if deps.respond_to?(:event_bus) && deps.event_bus
          deps.event_bus.emit(Textus::Event::ProposalAccepted.new(
                                proposal_key: command.pending_key,
                                target_key: target,
                                role: call.role,
                                occurred_at: call.now,
                              ))
        end
        Value::Result.success("protocol" => Textus::PROTOCOL, "accepted" => command.pending_key,
                              "target_key" => target, "action" => action, "cascade_key" => target)
      end

      def self.reject_proposal(command, call, deps)
        mentry = deps.manifest.resolver.resolve(command.pending_key).entry
        unless mentry.in_proposal_lane?(deps.manifest.policy)
          return Value::Result.failure(:proposal_error,
                                       "reject: '#{command.pending_key}' is not in a proposal zone (zone=#{mentry.lane})")
        end

        reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
        env = reader.read(command.pending_key)
        proposal = env&.meta&.dig("proposal") or
          return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
        target_key = proposal["target_key"]

        writer = Store::Entry::Writer.new(
          file_store: deps.file_store, manifest: deps.manifest,
          schemas: deps.schemas, audit_log: deps.audit_log,
          call: call, reader: reader, layout: deps.layout
        )
        writer.delete(command.pending_key, mentry: mentry)
        if deps.respond_to?(:event_bus) && deps.event_bus
          deps.event_bus.emit(Textus::Event::ProposalRejected.new(
                                proposal_key: command.pending_key,
                                role: call.role,
                                reason: command.reason,
                                occurred_at: call.now,
                              ))
        end
        result = { "protocol" => Textus::PROTOCOL, "rejected" => command.pending_key, "target_key" => target_key }
        result["reason"] = command.reason if command.reason
        Value::Result.success(result)
      end

      def self.enqueue_job(command, call, deps)
        action_class = Textus::Jobs.fetch(command.type.to_s)

        if action_class.const_defined?(:REQUIRED_ROLE) && call.role != action_class::REQUIRED_ROLE
          return Value::Result.failure(:forbidden,
                                       "role '#{call.role}' is not authorized to enqueue this job type",
                                       details: { "role" => call.role, "required_role" => action_class::REQUIRED_ROLE })
        end

        job = Textus::Store::Jobs::Queue::Job.new(type: command.type, args: command.args, role: call.role, max_attempts: 3)
        Textus::Store::Jobs::Queue.new(store: deps.job_store).enqueue(job)
        Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "id" => job.id)
      rescue Textus::UsageError
        Value::Result.failure(:usage_error, "unregistered job type '#{command.type}'")
      end

      def self.data_mv(command, _call, deps)
        manifest = deps.manifest
        geom = deps.layout

        return Value::Result.failure(:usage_error, "from and to required") if command.from.nil? || command.to.nil?
        unless manifest.data.declared_lane_kinds.key?(command.from)
          return Value::Result.failure(:usage_error,
                                       "data lane '#{command.from}' not declared")
        end

        dest_dir = geom.lane_path(command.to)
        return Value::Result.failure(:usage_error, "destination 'data/#{command.to}' already exists") if File.exist?(dest_dir)

        affected_keys = manifest.data.entries.select { |entry| entry.lane == command.from }.map(&:key)

        steps = [{ "op" => "rename_zone", "from" => command.from, "to" => command.to }]
        steps += affected_keys.map do |key|
          { "op" => "mv", "from" => key, "to" => "#{command.to}#{key[command.from.length..]}" }
        end

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: [])
        return Value::Result.success(plan) if command.dry_run

        rewrite_manifest!(geom, from: command.from, to: command.to)
        FileUtils.mv(geom.lane_path(command.from), dest_dir)
        Value::Result.success(plan)
      end

      def self.rewrite_manifest!(geom, from:, to:)
        path = geom.manifest_path
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
