require "forwardable"

module Textus
  module Protocol
    class Session
      attr_reader :role, :container, :gate, :node_stack

      DOMAIN_ACTIONS = (ActionRegistry::ENTRY_ACTIONS + ActionRegistry::OPS_ACTIONS + ActionRegistry::NODE_ACTIONS).to_set.freeze

      def self.open(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false)
        root = File.expand_path(root)
        container = Builder.new.call(root)
        gate = container.gate
        session = new(gate:, container:, role: role.to_s, correlation_id: correlation_id || SecureRandom.uuid, dry_run:)
        first_node = session.loop_node_names.first
        session.node_enter([first_node]) if first_node
        session
      end

      def initialize(gate:, container:, role:, correlation_id:, dry_run: false)
        @gate = gate
        @container = container
        @role = role
        @correlation_id = correlation_id
        @dry_run = dry_run
        @node_stack = []
      end

      def method_missing(name, *args, **kwargs)
        if DOMAIN_ACTIONS.include?(name)
          raise ArgumentError.new("#{name} accepts keyword arguments only") unless args.empty?

          request = Adapters::Request.new(
            action: name, params: kwargs, role: @role,
            session_id: @correlation_id, correlation_id: @correlation_id,
          )
          response = @gate.dispatch(request)
          raise response.error if response.error
          response.payload
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        DOMAIN_ACTIONS.include?(name) || super
      end

      def with_correlation_id(cid)
        self.class.new(gate: @gate, container: @container, role: @role,
                       correlation_id: cid, dry_run: @dry_run)
      end

      def with_role(new_role)
        self.class.new(gate: @gate, container: @container, role: new_role.to_s,
                       correlation_id: SecureRandom.uuid, dry_run: @dry_run)
      end

      def advance_cursor(new_cursor)
        @correlation_id = new_cursor.to_s
        self
      end

      def dry_run? = @dry_run

      def cursor
        @container.store.audit_log.latest[:seq]
      end

      def contract_etag
        Value::Etag.for_contract(@container.layout)
      end

      def check_etag!(observed_etag)
        return if observed_etag == contract_etag

        raise Textus::ContractDrift.new(
          "contract changed (was #{short_etag(contract_etag)}, now #{short_etag(observed_etag)})",
        )
      end

      def propose_lane
        @container.manifest.policy.propose_lane_for(@role)
      end

      # Container shortcuts
      def layout   = @container.layout
      def manifest = @container.manifest
      def schemas  = @container.schemas
      def store    = @container.store
      def root     = @container.layout.root

      # Loop navigation (in-memory node stack)
      require_relative "session/node_entry"

      def loop_node_names
        manifest.data.entries
          .select { |e| e.key.start_with?("knowledge.loop.") && e.key.count(".") == 2 }
          .map { |e| e.key.split(".").last.to_sym }
      end

      def current_node
        @node_stack.reverse_each.find(&:current?) || @node_stack.last
      end

      def node_enter(path)
        segments = path.map { |s| s.is_a?(String) && !s.match?(/\A[0-9]|-/) ? s.to_sym : s }
        Loop::Transitions.validate!(current_node&.path, segments, node_names: loop_node_names)

        current = current_node
        changing_node = current&.current? && current.node != segments.first
        fire_node_exit(current) if changing_node

        entry = NodeEntry.new(path: segments)
        @node_stack.push(entry)

        fire_node_enter(entry) if changing_node || @node_stack.size == 1
        entry
      end

      def node_exit
        entry = current_node
        raise Textus::UsageError.new("no node to exit") unless entry

        to_remove = @node_stack.reverse_each.with_object([]) do |e, acc|
          break acc if e.node != entry.node
          acc << e
        end

        to_remove.each { |e| @node_stack.delete(e) }
        fire_node_enter(current_node) if current_node
        entry
      end

      def node_back
        entry = current_node
        raise Textus::UsageError.new("no node to step back from") unless entry

        @node_stack.delete(entry)
        fire_node_enter(current_node) if current_node&.current?
        entry
      end

      def node_switch(path)
        node_exit
        node_enter(path)
      end

      def node_status
        current = current_node
        {
          current_node: current&.node&.to_s,
          current_topic: current&.topic&.to_s,
          current_item: current&.item&.to_s,
          stack: node_stack_summary,
          available_nodes: loop_node_names.map(&:to_s),
        }
      end

      def node_stack_summary
        @node_stack.map do |e|
          {
            path: e.path.map(&:to_s),
            entered_at: e.entered_at.iso8601,
            exited_at: e.exited_at&.iso8601,
            current: e.current?,
            duration_s: e.duration,
          }
        end
      end

      private

      def fire_node_enter(entry)
        request = Adapters::Request.new(
          action: :node_entered,
          params: { path: entry.path.map(&:to_s) },
          role: @role,
        )
        @gate.dispatch(request)
      rescue StandardError
        nil
      end

      def fire_node_exit(entry)
        entry.exited_at = Time.now.utc
        request = Adapters::Request.new(
          action: :node_exited,
          params: { path: entry.path.map(&:to_s) },
          role: @role,
        )
        @gate.dispatch(request)
      rescue StandardError
        nil
      end

      def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]
    end
  end
end
