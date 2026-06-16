# frozen_string_literal: true

module Textus
  module Action
    class Rdeps < Base
      extend Textus::Contract::DSL

      verb :rdeps
      summary "List the derived entries that depend on a key (reverse deps / impact set)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key whose dependents (what would be stranded if it moved) you want"

      def initialize(key:)
        super()
        @key = key
      end

      def call(container:, **)
        manifest = container.manifest
        rdeps = manifest.data.entries.each_with_object([]) do |entry, acc|
          next unless entry.external?

          sources = Array(entry.source&.sources).compact
          acc << entry.key if sources.any? { |source| source == @key || @key.start_with?("#{source}.") }
        end
        { "key" => @key, "rdeps" => rdeps }
      end

      def self.new(*args, **kwargs)
        return super(**kwargs) unless args.any?

        positional = instance_method(:initialize).parameters.slice(:keyreq, :key).map(&:last)
        mapped = positional.zip(args).to_h
        super(**mapped.merge(kwargs))
      end
    end
  end
end
