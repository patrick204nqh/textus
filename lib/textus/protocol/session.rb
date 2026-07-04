module Textus
  module Protocol
    class Session
      attr_reader :context, :bridge

      DOMAIN_VERBS = (VerbRegistry::ENTRY_VERBS + VerbRegistry::OPS_VERBS).to_set.freeze

      def self.open(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false)
        root = File.expand_path(root)
        container = Protocol::Builder.new.call(root)
        gate = container.gate
        bridge = Session::Bridge.new(container:, gate:)
        context = Session::Context.new(
          role: role.to_s,
          correlation_id: correlation_id || SecureRandom.uuid,
          dry_run: dry_run,
          cursor: container.store.event_store.latest_seq,
          contract_etag: Value::Etag.for_contract(bridge.layout),
          propose_lane: container.manifest.policy.propose_lane_for(role.to_s),
        )
        new(bridge:, context:)
      end

      def initialize(bridge:, context:)
        @bridge = bridge
        @context = context
      end

      # Context-derived
      def role = context.role
      def cursor = context.cursor
      def correlation_id = context.correlation_id
      def contract_etag = context.contract_etag
      def propose_lane = context.propose_lane
      def dry_run? = context.dry_run

      # Bridge-derived
      def root = bridge.root
      def container = bridge.container
      def store = bridge.store
      def manifest = bridge.manifest
      def schemas = bridge.schemas
      def layout = bridge.layout
      def workflows = bridge.workflows
      def gate = bridge.gate
      def ttl_evaluator = bridge.ttl_evaluator

      def method_missing(name, *args, **kwargs)
        if DOMAIN_VERBS.include?(name)
          raise ArgumentError.new("#{name} accepts keyword arguments only") unless args.empty?

          return bridge.dispatch(role.to_sym, name, kwargs, call: context.call)
        end

        return bridge.public_send(name, *args, **kwargs) if bridge.respond_to?(name)

        super
      end

      def respond_to_missing?(name, include_private = false)
        DOMAIN_VERBS.include?(name) || bridge.respond_to?(name) || super
      end

      def with_correlation_id(cid)
        self.class.new(bridge:, context: context.with(correlation_id: cid))
      end

      def with_role(new_role)
        self.class.new(
          bridge:,
          context: context.with(
            role: new_role.to_s,
cursor: container.store.audit_log.latest[:seq],
            contract_etag: Value::Etag.for_contract(container.layout),
            propose_lane: manifest.policy.propose_lane_for(new_role.to_s),
          ),
        )
      end

      def advance_cursor(new_cursor)
        @context = context.with(cursor: new_cursor)
        self
      end

      def check_etag!(observed_etag)
        return if observed_etag == contract_etag

        raise Textus::ContractDrift.new(
          "contract changed (was #{short_etag(contract_etag)}, now #{short_etag(observed_etag)})",
        )
      end

      private

      def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]
    end
  end
end
