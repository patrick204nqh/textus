module Textus
  class Manifest
    class Rules
      RuleSet = ::Data.define(:handler_allowlist, :guard, :lifecycle)
      EMPTY_SET = RuleSet.new(handler_allowlist: nil, guard: nil, lifecycle: nil)

      def self.parse(raw)
        new(Array(raw).map { |b| Block.new(b) })
      end

      def initialize(blocks)
        @blocks = blocks
      end

      attr_reader :blocks

      def for(key)
        slots = { handler_allowlist: [], guard: [], lifecycle: [] }
        @blocks.each do |b|
          next unless Textus::Domain::Policy::Matcher.matches?(b.match, key)

          slots.each_key { |slot| slots[slot] << b if b.public_send(slot) }
        end
        RuleSet.new(
          handler_allowlist: pick(slots[:handler_allowlist], :handler_allowlist, key),
          guard: pick(slots[:guard], :guard, key),
          lifecycle: pick(slots[:lifecycle], :lifecycle, key),
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
        attr_reader :match, :handler_allowlist, :guard, :lifecycle

        def initialize(raw)
          @match = raw["match"] or raise Textus::UsageError.new("rule block missing match:")
          @handler_allowlist = parse_handler_allowlist(raw["intake_handler_allowlist"])
          @guard = parse_guard(raw["guard"])
          @lifecycle = parse_lifecycle(raw["lifecycle"])
        end

        private

        def parse_handler_allowlist(arr)
          return nil if arr.nil?

          Textus::Domain::Policy::HandlerAllowlist.new(handlers: arr)
        end

        # A guard: block is a map of transition => [predicate specs]. Predicate
        # names are validated at GuardFactory build time via Predicates::Registry
        # (ADR 0031); here we only assert the structural shape.
        def parse_guard(h)
          return nil if h.nil?
          raise Textus::BadManifest.new("guard: must be a map of transition => [predicates]") unless h.is_a?(Hash)

          h
        end

        def parse_lifecycle(h)
          return nil if h.nil?

          Textus::Domain::Policy::Lifecycle.new(
            ttl: h["ttl"],
            on_expire: h["on_expire"],
            budget_ms: h["budget_ms"],
          )
        end
      end
    end
  end
end
