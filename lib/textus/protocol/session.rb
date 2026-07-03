module Textus
  module Protocol
    class Session
      attr_reader :role, :cursor, :root, :container, :correlation_id, :contract_etag

      DOMAIN_VERBS = (Textus::Protocol::VerbRegistry::ENTRY_VERBS + Textus::Protocol::VerbRegistry::OPS_VERBS).to_set.freeze

      def initialize(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false)
        @root = File.expand_path(root)
        @container = Infra::Store::Builder.new.call(@root)
        @role = role.to_s
        @correlation_id = correlation_id || SecureRandom.uuid
        @dry_run = dry_run
        @cursor = container.audit_log.latest_seq
        @contract_etag = Value::Etag.for_contract(@root)
      end

      def dry_run? = @dry_run

      def method_missing(name, *args, **kwargs)
        return super unless DOMAIN_VERBS.include?(name)

        raise ArgumentError.new("#{name} accepts keyword arguments only") unless args.empty?

        call_obj = Value::Call.build(role: @role, correlation_id: @correlation_id)
        container.gate.dispatch(@role.to_sym, name, kwargs, call: call_obj)
      end

      def respond_to_missing?(name, include_private = false)
        DOMAIN_VERBS.include?(name) || super
      end

      def with_role(new_role)
        self.class.allocate.tap do |s|
          s.instance_variable_set(:@root, @root)
          s.instance_variable_set(:@container, @container)
          s.instance_variable_set(:@role, new_role.to_s)
          s.instance_variable_set(:@correlation_id, @correlation_id || SecureRandom.uuid)
          s.instance_variable_set(:@dry_run, @dry_run)
          s.instance_variable_set(:@cursor, build_cursor)
          s.instance_variable_set(:@contract_etag, build_contract_etag)
        end
      end

      def advance_cursor(new_cursor)
        @cursor = new_cursor
      end

      def check_etag!(observed_etag)
        return if observed_etag == @contract_etag

        raise Textus::ContractDrift.new(
          "contract changed (was #{short_etag(@contract_etag)}, now #{short_etag(observed_etag)})",
        )
      end

      private

      def build_cursor
        container.audit_log.latest_seq
      end

      def build_contract_etag
        Value::Etag.for_contract(@root)
      end

      def short_etag(etag) = etag.to_s.delete_prefix("sha256:")[0, 8]
    end
  end
end
