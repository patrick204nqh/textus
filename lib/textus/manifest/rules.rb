module Textus
  class Manifest
    class Rules
      RuleSet = Data.define(:refresh, :handler_allowlist, :promote, :retention)
      EMPTY_SET = RuleSet.new(refresh: nil, handler_allowlist: nil, promote: nil, retention: nil)

      def self.parse(raw)
        new(Array(raw).map { |b| Block.new(b) })
      end

      def initialize(blocks)
        @blocks = blocks
      end

      attr_reader :blocks

      def for(key)
        slots = { refresh: [], handler_allowlist: [], promote: [], retention: [] }
        @blocks.each do |b|
          next unless Textus::Domain::Policy::Matcher.matches?(b.match, key)

          slots.each_key { |slot| slots[slot] << b if b.public_send(slot) }
        end
        RuleSet.new(
          refresh: pick(slots[:refresh], :refresh, key),
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
        attr_reader :match, :refresh, :handler_allowlist, :promote, :retention

        def initialize(raw)
          @match = raw["match"] or raise Textus::UsageError.new("rule block missing match:")
          if raw.key?("handler_allowlist")
            raise Textus::BadManifest.new(
              "'handler_allowlist:' was renamed to 'intake_handler_allowlist:' in textus/3.",
              hint: "Run `textus migrate --to=textus/3`.",
            )
          end
          @refresh = parse_refresh(raw["refresh"])
          @handler_allowlist = parse_handler_allowlist(raw["intake_handler_allowlist"])
          @promote = parse_promote(raw["promote_requires"])
          @retention = raw["retention"] # reserved — passthrough only
        end

        private

        def parse_refresh(h)
          return nil if h.nil?

          Textus::Domain::Policy::Refresh.new(
            ttl: h["ttl"],
            on_stale: h["on_stale"] || "warn",
            sync_budget_ms: h["sync_budget_ms"],
          )
        end

        def parse_handler_allowlist(arr)
          return nil if arr.nil?

          Textus::Domain::Policy::HandlerAllowlist.new(handlers: arr)
        end

        def parse_promote(arr)
          return nil if arr.nil?

          Textus::Domain::Policy::Promote.new(requires: arr)
        end
      end
    end
  end
end
