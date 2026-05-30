module Textus
  class Manifest
    class Rules
      RuleSet = ::Data.define(:fetch, :handler_allowlist, :promote, :retention)
      EMPTY_SET = RuleSet.new(fetch: nil, handler_allowlist: nil, promote: nil, retention: nil)

      def self.parse(raw)
        new(Array(raw).map { |b| Block.new(b) })
      end

      def initialize(blocks)
        @blocks = blocks
      end

      attr_reader :blocks

      def for(key)
        slots = { fetch: [], handler_allowlist: [], promote: [], retention: [] }
        @blocks.each do |b|
          next unless Textus::Domain::Policy::Matcher.matches?(b.match, key)

          slots.each_key { |slot| slots[slot] << b if b.public_send(slot) }
        end
        RuleSet.new(
          fetch: pick(slots[:fetch], :fetch, key),
          handler_allowlist: pick(slots[:handler_allowlist], :handler_allowlist, key),
          promote: pick(slots[:promote], :promote, key),
          retention: pick(slots[:retention], :retention, key),
        )
      end

      def explain(key)
        @blocks.select { |b| Textus::Domain::Policy::Matcher.matches?(b.match, key) }
      end

      private

      def pick(blocks, slot, key)
        return nil if blocks.empty?

        globs = blocks.map(&:match)
        winning = Textus::Domain::Policy::Matcher.pick_most_specific(globs, key: key)
        blocks.find { |b| b.match == winning }&.public_send(slot)
      end

      class Block
        attr_reader :match, :fetch, :handler_allowlist, :promote, :retention

        def initialize(raw)
          @match = raw["match"] or raise Textus::UsageError.new("rule block missing match:")
          @fetch = parse_fetch(raw["fetch"])
          @handler_allowlist = parse_handler_allowlist(raw["intake_handler_allowlist"])
          @promote = parse_promotion(raw["promotion"])
          @retention = parse_retention(raw["retention"])
        end

        private

        def parse_fetch(h)
          return nil if h.nil?

          Textus::Domain::Policy::Fetch.new(
            ttl: h["ttl"],
            on_stale: h["on_stale"] || "warn",
            sync_budget_ms: h["sync_budget_ms"],
            fetch_timeout_seconds: h["fetch_timeout_seconds"],
          )
        end

        def parse_handler_allowlist(arr)
          return nil if arr.nil?

          Textus::Domain::Policy::HandlerAllowlist.new(handlers: arr)
        end

        def parse_promotion(h)
          return nil if h.nil?

          raise Textus::BadManifest.new("promotion: must be a hash with a 'requires:' array") unless h.is_a?(Hash) && h.key?("requires")

          Textus::Domain::Policy::Promote.new(requires: Array(h["requires"]))
        end

        def parse_retention(h)
          return nil if h.nil?

          Textus::Domain::Policy::Retention.new(
            expire_after: h["expire_after"],
            archive_after: h["archive_after"],
          )
        end
      end
    end
  end
end
