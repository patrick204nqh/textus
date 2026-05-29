module Textus
  module Doctor
    # Abstract base for a single doctor check. Each concrete check inspects
    # one slice of store health and returns an array of issue hashes:
    #   { "code" => String, "level" => "error"|"warning"|"info",
    #     "subject" => String, "message" => String, "fix" => String (optional) }
    class Check
      # Snake-case name used in --checks flag and ALL_CHECKS list. Default
      # derives from the class name; override if the SPEC name diverges.
      def self.name_key
        @name_key ||= name.split("::").last
                          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                          .downcase
      end

      def initialize(container_or_session)
        @container = container_or_session
      end

      def call
        raise NotImplementedError.new("#{self.class.name}#call not implemented")
      end

      protected

      # Accepts either a Textus::Container (preferred) or a legacy
      # Textus::Session (which exposes the same fields through read_caps).
      def root
        @container.is_a?(Textus::Container) ? @container.root : @container.read_caps.root
      end

      def manifest
        @container.is_a?(Textus::Container) ? @container.manifest : @container.read_caps.manifest
      end

      def rpc = @container.rpc

      # Dispatch a verb. Works whether initialized with a Container (the new
      # API) or a legacy Session.
      def dispatch(verb, *, **)
        if @container.is_a?(Textus::Container)
          klass = Textus::Dispatcher.fetch(verb)
          call_value = Textus::Call.build(role: Textus::Role::DEFAULT)
          init_kwargs = { container: @container, call: call_value }
          params = klass.instance_method(:initialize).parameters.map { |_, n| n }
          init_kwargs[:hook_context] = nil if params.include?(:hook_context)
          klass.new(**init_kwargs).call(*, **)
        else
          @container.public_send(verb, *, **)
        end
      end
    end
  end
end
