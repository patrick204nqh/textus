module Textus
  class Store
    class CommandModel
      def initialize(bus:, role:, correlation_id: nil)
        @bus = bus
        @role = role.to_s
        @correlation_id = correlation_id || SecureRandom.uuid
      end

      def get(key)
        command = Contracts::GetEntry.new(key: key)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def put(key, meta: nil, body: nil, content: nil, if_etag: nil)
        command = Contracts::PutEntry.new(key: key, meta: meta, body: body, content: content, if_etag: if_etag)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def list(prefix: nil, lane: nil)
        command = Contracts::ListKeys.new(prefix: prefix, lane: lane)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def delete(key, if_etag: nil)
        command = Contracts::DeleteKey.new(key: key, if_etag: if_etag)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def move(old_key:, new_key:, if_etag: nil)
        command = Contracts::MoveKey.new(old_key: old_key, new_key: new_key, if_etag: if_etag)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def propose(key, meta: nil, body: nil, content: nil)
        command = Contracts::ProposeEntry.new(key: key, meta: meta, body: body, content: content)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def accept(pending_key)
        command = Contracts::AcceptProposal.new(pending_key: pending_key)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def reject(pending_key)
        command = Contracts::RejectProposal.new(pending_key: pending_key)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def enqueue(type, args: {})
        command = Contracts::EnqueueJob.new(type: type, args: args)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def ingest(kind:, slug:, url: nil, path: nil, zone: nil, label: nil)
        command = Contracts::IngestEntry.new(kind: kind, slug: slug, url: url, path: path, zone: zone, label: label)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def drain(prefix: nil, lane: nil)
        command = Contracts::DrainStore.new(prefix: prefix, lane: lane)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def jobs(state: "ready", action: nil, job_id: nil)
        command = Contracts::JobsAction.new(state: state, action: action, job_id: job_id)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def rule_lint(candidate_yaml:)
        command = Contracts::RuleLint.new(candidate_yaml: candidate_yaml)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def data_mv(from:, to:, dry_run: false)
        command = Contracts::DataMv.new(from: from, to: to, dry_run: dry_run)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def key_mv_prefix(from_prefix:, to_prefix:, dry_run: false)
        command = Contracts::KeyMvPrefix.new(from_prefix: from_prefix, to_prefix: to_prefix, dry_run: dry_run)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def key_delete_prefix(prefix:, dry_run: false)
        command = Contracts::KeyDeletePrefix.new(prefix: prefix, dry_run: dry_run)
        call = Value::Call.build(role: @role, correlation_id: @correlation_id)
        @bus.dispatch(command, call: call)
      end

      def with_role(role)
        self.class.new(bus: @bus, role: role, correlation_id: @correlation_id)
      end

      def with_correlation_id(cid)
        self.class.new(bus: @bus, role: @role, correlation_id: cid)
      end
    end
  end
end
