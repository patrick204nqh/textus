# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class Where < Base
        extend Textus::Contract::DSL

        verb :where
        summary "Resolve a key to its zone, owner, and path without reading the body."
        surfaces :cli, :mcp
        arg :key, String, required: true, positional: true,
                          description: "dotted key to locate (returns zone, owner, path; does not read content)"

        BURN = :sync

        def initialize(key:)
          super()
          @key = key
        end

        def args = { key: @key }

        def call(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
          manifest = container.manifest
          res = manifest.resolver.resolve(@key)
          mentry = res.entry
          path = res.path
          { "protocol" => PROTOCOL, "key" => @key, "lane" => mentry.lane, "owner" => mentry.owner, "path" => path }
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
end
