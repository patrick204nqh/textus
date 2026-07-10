require "forwardable"

module Textus
  module Protocol
    class Session
      attr_reader :role, :container, :gate

      def self.open(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false)
        root = File.expand_path(root)
        container = Builder.new.call(root)
        gate = container.gate
        new(gate:, container:, role: role.to_s, correlation_id: correlation_id || SecureRandom.uuid, dry_run:)
      end

      def initialize(gate:, container:, role:, correlation_id:, dry_run: false)
        @gate = gate
        @container = container
        @role = role
        @correlation_id = correlation_id
        @dry_run = dry_run
      end

      DOMAIN_ACTIONS = (ActionRegistry::ENTRY_ACTIONS + ActionRegistry::OPS_ACTIONS + ActionRegistry::NODE_ACTIONS).to_set.freeze

      def method_missing(name, *args, **kwargs)
        if DOMAIN_ACTIONS.include?(name)
          raise ArgumentError.new("#{name} accepts keyword arguments only") unless args.empty?

          request = Protocol::Message::Request.new(
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

      def dry_run? = @dry_run

      def advance_cursor(new_cursor)
        @correlation_id = new_cursor.to_s
        self
      end
      def cursor = @container.store.audit_log.latest[:seq]
      def contract_etag = Value::Etag.for_contract(@container.layout)

      def check_etag!(observed_etag)
        return if observed_etag == contract_etag

        raise Textus::ContractDrift.new(
          "contract changed (was #{short_etag(contract_etag)}, now #{short_etag(observed_etag)})",
        )
      end

      def propose_lane
        @container.manifest.policy.propose_lane_for(@role)
      end

      def layout   = @container.layout
      def manifest = @container.manifest
      def schemas  = @container.schemas
      def store    = @container.store
      def root     = @container.layout.root

      private

      def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]
    end
  end
end
