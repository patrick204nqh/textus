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

      def initialize(container)
        @container = container
      end

      def call
        raise NotImplementedError.new("#{self.class.name}#call not implemented")
      end

      protected

      def root     = @container.root
      def manifest = @container.manifest
      def steps    = @container.steps

      # Dispatch a verb through Gate.
      def dispatch(verb, *_args, **kwargs)
        cmd_class = Textus::Gate::VERB_COMMAND.fetch(verb)
        merged = kwargs.merge(role: Textus::Role::DEFAULT)
        cmd = cmd_class.new(**merged.slice(*cmd_class.members))
        @container.gate.dispatch(cmd, container: @container)
      end
    end
  end
end
