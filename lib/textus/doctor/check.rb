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

      def initialize(container, role: Textus::Value::Role::DEFAULT)
        @container = container
        @role      = role
      end

      def call
        raise NotImplementedError.new("#{self.class.name}#call not implemented")
      end

      protected

      def root     = @container.root
      def geometry = @container.layout
      def manifest = @container.manifest

      def dispatch(verb, *args, **kwargs)
        contract_class = Textus::VerbRegistry.contract_class_for(verb)
        members = contract_class.members
        command_kwargs = members.each_with_index.to_h { |m, i| [m, args[i] || kwargs[m]] }
        command = contract_class.new(**command_kwargs)
        call = Textus::Value::Call.build(role: @role)
        result = @container.pipeline.dispatch(command, call: call)
        Textus::Value::Result.extract(result)
      end
    end
  end
end
