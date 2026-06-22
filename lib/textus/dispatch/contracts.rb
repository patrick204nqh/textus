module Textus
  module Dispatch
    module Contracts
      GetEntry = Data.define(:key) do
        def self.from_wire(args)
          new(key: args["key"])
        end
      end

      PutEntry = Data.define(:key, :meta, :body, :content, :if_etag) do
        def self.from_wire(args)
          new(
            key: args["key"],
            meta: args["_meta"],
            body: args["body"],
            content: args["content"],
            if_etag: args["if_etag"],
          )
        end
      end

      ListKeys = Data.define(:prefix, :lane) do
        def self.from_wire(args)
          new(prefix: args["prefix"], lane: args["lane"])
        end
      end

      DeleteKey = Data.define(:key, :if_etag) do
        def self.from_wire(args)
          new(key: args["key"], if_etag: args["if_etag"])
        end
      end

      MoveKey = Data.define(:old_key, :new_key, :if_etag, :dry_run) do
        def self.from_wire(args)
          new(old_key: args["old_key"], new_key: args["new_key"], if_etag: args["if_etag"], dry_run: args["dry_run"])
        end
      end

      ProposeEntry = Data.define(:key, :meta, :body, :content) do
        def self.from_wire(args)
          new(key: args["key"], meta: args["_meta"], body: args["body"], content: args["content"])
        end
      end

      AcceptProposal = Data.define(:pending_key) do
        def self.from_wire(args)
          new(pending_key: args["pending_key"])
        end
      end

      RejectProposal = Data.define(:pending_key) do
        def self.from_wire(args)
          new(pending_key: args["pending_key"])
        end
      end

      EnqueueJob = Data.define(:type, :args) do
        def self.from_wire(args)
          new(type: args["type"], args: args["args"] || {})
        end
      end

      AuditEntries = Data.define(:key, :lane, :role, :verb, :since, :seq_since, :correlation_id, :limit)

      PulseEntries = Data.define(:since) do
        def self.from_wire(args)
          new(since: args["since"])
        end
      end

      BlameEntry = Data.define(:key, :limit) do
        def self.from_wire(args)
          new(key: args["key"], limit: args["limit"])
        end
      end

      WhereEntry = Data.define(:key)

      UidEntry = Data.define(:key)

      DepsEntry = Data.define(:key)

      RdepsEntry = Data.define(:key)

      BootStore = Data.define

      DoctorStore = Data.define(:checks) do
        def self.from_wire(args)
          new(checks: args["checks"])
        end
      end

      PublishedEntries = Data.define

      RuleExplain = Data.define(:key, :detail) do
        def self.from_wire(args)
          new(key: args["key"], detail: args["detail"])
        end
      end

      RuleList = Data.define

      SchemaEnvelope = Data.define(:key)

      DrainStore = Data.define(:prefix, :lane) do
        def self.from_wire(args)
          new(prefix: args["prefix"], lane: args["lane"])
        end
      end

      IngestEntry = Data.define(:kind, :slug, :url, :path, :zone, :label) do
        def self.from_wire(args)
          new(kind: args["kind"], slug: args["slug"], url: args["url"],
              path: args["path"], zone: args["zone"], label: args["label"])
        end
      end

      JobsAction = Data.define(:state, :action, :job_id) do
        def self.from_wire(args)
          new(state: args["state"] || "ready", action: args["action"], job_id: args["job_id"])
        end
      end

      RuleLint = Data.define(:candidate_yaml) do
        def self.from_wire(args)
          new(candidate_yaml: args["candidate_yaml"] || args["against"])
        end
      end

      DataMv = Data.define(:from, :to, :dry_run) do
        def self.from_wire(args)
          new(from: args["from"], to: args["to"], dry_run: args["dry_run"] || false)
        end
      end

      KeyMvPrefix = Data.define(:from_prefix, :to_prefix, :dry_run) do
        def self.from_wire(args)
          new(from_prefix: args["from_prefix"], to_prefix: args["to_prefix"], dry_run: args["dry_run"] || false)
        end
      end

      KeyDeletePrefix = Data.define(:prefix, :dry_run) do
        def self.from_wire(args)
          new(prefix: args["prefix"], dry_run: args["dry_run"] || false)
        end
      end
    end
  end
end
