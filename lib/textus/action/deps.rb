# frozen_string_literal: true

module Textus
  module Action
    class Deps < Base
      extend Textus::Contract::DSL

      verb :deps
      summary "List the keys a derived entry depends on (its projection/external sources)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key of the derived entry whose source keys you want"


      def initialize(key:)
        super()
        @key = key
      end

      def call(container:, **)
        entry = container.manifest.data.entries.find { |e| e.key == @key }
        deps = entry&.external? ? Array(entry.source&.sources).compact : []
        { "key" => @key, "deps" => deps.uniq }
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
