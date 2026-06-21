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

      def self.call(container:, call:, key:)
        envelope = container.compositor.read(key)
        return nil unless envelope

        entry = container.manifest.resolver.resolve(key).entry
        file_stat = Textus::Port::Storage::FileStat.new
        envelope.with(freshness: freshness_evaluator(container, call, file_stat).verdict(entry))
      end

      def self.freshness_evaluator(container, call, file_stat)
        Textus::Core::Freshness::Evaluator.new(
          manifest: container.manifest,
          file_stat: file_stat,
          clock: call,
        )
      end
    end
  end
end
