# frozen_string_literal: true

module Textus
  module Action
    class Get < Base
      extend Textus::Contract::DSL

      verb :get
      summary "Read one entry - a pure on-disk read annotated with a freshness " \
              "verdict; never ingests (quarantine freshness is drain + hook " \
              "only, ADR 0089). Returns the envelope (uid, etag, _meta, body, " \
              "freshness)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to read, e.g. 'knowledge.project'"
      view { |v, _i| v.to_h_for_wire }

      def initialize(key:)
        super()
        @key = key
      end

      def call(container:, call:, file_stat: Textus::Port::Storage::FileStat.new)
        @container = container
        @call = call
        @manifest = container.manifest
        @file_store = container.file_store
        @file_stat = file_stat
        annotated_envelope(@key)
      end

      def self.new(*args, **kwargs)
        return super(**kwargs) unless args.any?

        positional = instance_method(:initialize).parameters.slice(:keyreq, :key).map(&:last)
        mapped = positional.zip(args).to_h
        super(**mapped.merge(kwargs))
      end

      private

      def annotated_envelope(key)
        envelope = read_raw_envelope(key)
        return nil if envelope.nil?

        entry = @manifest.resolver.resolve(key).entry
        envelope.with(freshness: evaluator.verdict(entry))
      end

      def evaluator
        @evaluator ||= Textus::Core::Freshness::Evaluator.new(
          manifest: @manifest,
          file_stat: @file_stat,
          clock: @call,
        )
      end

      def read_raw_envelope(key)
        res = @manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
        return nil unless @file_store.exists?(path)

        raw = @file_store.read(path)
        parsed = Textus::Format.for(mentry.format).parse(raw, path: path)
        Textus::Envelope.build(
          key: key,
          mentry: mentry,
          path: path,
          meta: parsed["_meta"],
          body: parsed["body"],
          etag: Textus::Etag.for_bytes(raw),
          content: parsed["content"],
        )
      end
    end
  end
end
