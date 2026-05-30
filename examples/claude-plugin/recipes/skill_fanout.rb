# frozen_string_literal: true

# Recipe: fan one `intake.skills.<slug>` entry out into N derived
# `vendor.skills.<slug>.*` entries, one per file in the bundle.
#
# To use: copy this file into your store's hooks/ directory (e.g.
# .textus/hooks/skill_fanout.rb) and ensure the destination zone (`vendor`)
# is writable by the role that triggers the refresh. See
# docs/recipes/github-skill-bundle.md.

module TextusRecipes
  module SkillFanout
    SOURCE_PREFIX  = "intake.skills."
    DERIVED_PREFIX = "vendor.skills."

    def self.register
      Textus.hook do |reg|
        reg.on(:entry_refreshed, :skill_fanout, keys: "#{SOURCE_PREFIX}*") do |ctx:, key:, envelope:, **|
          next unless key.start_with?(SOURCE_PREFIX)

          slug = key.delete_prefix(SOURCE_PREFIX)
          files = envelope.dig("content", "files") || {}

          desired_keys = files.keys.map { |rel| TextusRecipes::SkillFanout.derived_key(slug, rel) }

          # `ctx:` routes all reads and writes through Operations so the
          # standard pipeline (authz, audit, schema validation, events) applies.
          # This listener is on :entry_refreshed; inner ctx.put fires :entry_put
          # (a different event), so no recursion guard is needed.
          existing_rows = ctx.list(prefix: "#{DERIVED_PREFIX}#{slug}")
          existing_keys = existing_rows.map { |row| row["key"] }

          (existing_keys - desired_keys).each do |orphan|
            ctx.delete(orphan, suppress_events: true)
          end

          files.each do |rel, bytes|
            ctx.put(
              TextusRecipes::SkillFanout.derived_key(slug, rel),
              meta: { "source_key" => key, "source_path" => rel },
              body: bytes,
            )
          end
        end
      end
    end

    def self.derived_key(slug, rel_path)
      "#{DERIVED_PREFIX}#{slug}.#{rel_path.tr("/", ".")}"
    end
  end
end

# Auto-register when loaded by the store's hook loader. `Textus.hook` simply
# queues the block, so this is safe to require from any context — the store's
# Loader drains and applies queued blocks against the active registry. Specs
# that load this file outside a store can call `Textus.drain_hook_blocks`
# directly.
TextusRecipes::SkillFanout.register
