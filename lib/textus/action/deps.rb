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

      BURN = :sync

      def initialize(key:)
        super()
        @key = key
      end

      def args = { key: @key }

      def call(container:, **)
        entry = container.manifest.data.entries.find { |e| e.key == @key }
        deps =
          if entry&.derived?
            src = entry.source
            if src.projection?
              Array(src.select).compact
            elsif src.external?
              Array(src.sources).compact
            else
              []
            end
          else
            []
          end
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
