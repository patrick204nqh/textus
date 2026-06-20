# frozen_string_literal: true

# Pure placement logic for the spec-layout guard (see spec/spec_layout_spec.rb).
#
# The convention: a spec that `describe`s a Textus:: *constant* must live in the
# directory mirroring that constant's namespace. A spec that `describe`s a
# *string* (integration/conformance) is exempt and may live anywhere.
#
# All methods are pure string logic — no I/O, no RSpec — so they unit-test
# directly.
module SpecLayout
  module_function

  # The constant named by the FIRST top-level `RSpec.describe`, if it is a
  # Textus:: constant. Returns e.g. "Textus::Port::BuildLock", or nil when the
  # spec describes a string or a non-Textus constant (both exempt). Stops at the
  # first whitespace/comma/`do`, so `describe Textus::Store, ".discover"` yields
  # "Textus::Store".
  def described_constant(source)
    source[/^\s*RSpec\.describe\s+(Textus(?:::[A-Za-z0-9_]+)+)/, 1]
  end

  # Normalize one path or namespace segment for case- and underscore-insensitive
  # comparison: "BuildLock" -> "buildlock", "build_lock" -> "buildlock",
  # "MCP" -> "mcp". This lets directory names compare against CamelCase constant
  # segments without a brittle snake_case round-trip (acronyms included).
  def normalize(segment)
    segment.downcase.delete("_")
  end

  # Given the described constant and the spec file's directory segments relative
  # to spec/ (e.g. ["ports"], or [] for the spec root), return nil if placement
  # is legal or a human-readable reason string if it violates the mirror rule.
  #
  # Rule: the (normalized) directory must be a prefix of the constant's full
  # normalized path (namespace segments + leaf class), AND must reach at least
  # the enclosing namespace (i.e. be missing at most the leaf class). That makes
  # a module-grouping spec (`describe Textus::Manifest` in spec/manifest/) legal,
  # and the same spec at the spec root legal too, while a nested unit spec
  # (`describe Textus::Port::BuildLock`) MUST sit under spec/ports/.
  def placement_error(constant, dir_segments)
    full = constant.split("::")[1..].map { |s| normalize(s) } # drop "Textus"
    dir  = dir_segments.map { |s| normalize(s) }

    return nil if dir == full[0, dir.length] && dir.length >= full.length - 1
    return nil if legacy_match?(full, dir)

    namespace = full[0, full.length - 1]
    expected  = namespace.empty? ? "the spec root" : "spec/#{namespace.join("/")}/"
    actual    = dir.empty? ? "the spec root" : "spec/#{dir.join("/")}/"
    "#{constant} should live under #{expected} (or spec/#{full.join("/")}/), not #{actual}"
  end

  def legacy_match?(full, dir)
    aliases = []

    if full.first == "value"
      aliases << []
    elsif full.first == "store"
      aliases << ["index"] if full[1] == "index"
      aliases << ["jobs"] if full[1] == "jobs"
      aliases << ["jobs", full[2]] if full[1] == "jobs" && full[2]
      aliases << ["envelope"] if full[1] == "envelope"
      aliases << ["envelope", full[2]] if full[1] == "envelope" && full[2]
      aliases << []
    elsif full.first == "port"
      aliases << ["ports", *full[1..]]
    elsif full[0, 2] == %w[surface cli]
      aliases << ["cli", *full[2..]]
      aliases << ["surfaces", "cli", *full[2..]]
    elsif full[0, 2] == %w[surface mcp]
      aliases << ["mcp", *full[2..]]
      aliases << ["surfaces", "mcp", *full[2..]]
    elsif full == %w[surface rolescope]
      aliases << []
      aliases << ["surfaces"]
    end

    aliases << ["domain", *full[1..]] if full.first == "core"
    aliases << ["domain", "policy", *full[2..]] if full[0, 2] == %w[manifest policy]

    aliases.any? { |alt| dir == alt[0, dir.length] && dir.length >= alt.length - 1 }
  end

  # ── Category-aware mirror (the post-Phase-1 rule) ─────────────────────────
  #
  # The restructure moves every spec under one of these top-level category
  # dirs; the lib/-mirror then applies BELOW the category segment. This logic
  # is written ahead of the move (with its own unit examples) and only becomes
  # the live sweep rule once the files have moved.
  CATEGORIES = %w[unit integration conformance].freeze

  # A spec is "store-backed" (integration, not a pure unit) when it stands up a
  # Store / tmpdir via the fixture or a preset helper. This is the same signal
  # the move used to classify specs, reused here so the unit/ category stays
  # pure: a store-backed spec under spec/unit/ is a misfile.
  STORE_BACKED = /
    include_context\s+["']textus_store_fixture | Dir\.mktmpdir | Textus::Store\.new |
    store_from_manifest | \b(?:minimal|machine|intake)_store\(
  /x

  def store_backed?(source) = source.match?(STORE_BACKED)

  # Zone-kind tokens a sweep has retired from the vocabulary (ADR 0092). A
  # retired token must not reappear in a spec body outside spec/support/ and the
  # dedicated kind-guards (RETIRED_TOKEN_GUARDS) that assert its rejection — so a
  # straggler left after a rename fails CI instead of lingering as noise. This is
  # a denylist of *dead* tokens, NOT a ban on live kinds: `machine`/`canon`/
  # `workspace`/`queue` are spelled freely in inline manifests, and `derived`
  # stays a live entry-kind word. Grows by one entry each time a kind is retired.
  RETIRED_KIND_TOKENS = %w[quarantine].freeze

  # Specs whose job IS to assert a retired token is rejected (or, for the guard's
  # own spec, that carry retired tokens as test data) — exempt from the scan.
  RETIRED_TOKEN_GUARDS = %w[
    schema_spec.rb capabilities_schema_spec.rb lanes_spec.rb spec_layout_spec.rb
  ].freeze

  # Retired tokens present in `source` as whole words, or [] when clean.
  def retired_kind_tokens(source)
    RETIRED_KIND_TOKENS.select { |t| source.match?(/\b#{Regexp.escape(t)}\b/) }
  end

  # Manifest-grammar tokens ADR 0093 retired: the `upkeep:` rule field and its
  # `on_change`/`source_change` discriminators, and the `on_expire:` action key.
  # Production now lives in `source:` (handler/template/command + ttl/on_write)
  # and age-GC in the `retention:` rule. A retired token must not reappear in a
  # spec body outside the guards that assert its rejection. NOT a ban on live
  # words: `template`/`project`/`source`/`retention` are spelled freely; `compute`
  # and `lifecycle`/`materialize` are omitted (they may appear in ADR prose).
  RETIRED_MANIFEST_TOKENS = %w[
    upkeep on_change source_change on_expire
    inject_boot provenance
  ].freeze

  # Specs allowed to mention the retired manifest tokens BECAUSE their job is to
  # assert those tokens are rejected, or they test the ADR 0094 publish-target
  # vocabulary where inject_boot/provenance appear in the new (permitted) context
  # (plus the guard's own spec, which carries them as test data).
  RETIRED_MANIFEST_TOKEN_GUARDS = %w[
    schema_spec.rb source_retention_load_spec.rb spec_layout_spec.rb
    data_publish_load_spec.rb
    publish_target_spec.rb source_spec.rb publish_targets_spec.rb
    render_spec.rb
    mcp_config_build_spec.rb plugin_manifest_build_spec.rb
    entry_spec.rb
  ].freeze

  # Retired manifest tokens present in `source` as whole words, or [] when clean.
  def retired_manifest_tokens(source)
    RETIRED_MANIFEST_TOKENS.select { |t| source.match?(/\b#{Regexp.escape(t)}\b/) }
  end

  # True when the top-level group describes a string literal (a cross-surface
  # conformance spec). Distinct from `described_constant` returning nil: that is
  # also nil for a non-Textus constant (e.g. `RSpec.describe SpecLayout`), which
  # is exempt from both the mirror rule AND the conformance rule.
  def string_described?(source) = source.match?(/^\s*RSpec\.describe\s+["']/)

  # Like `placement_error`, but for the categorized tree: the first dir segment
  # must be a known category, and the mirror rule applies to the remainder.
  # `dir_segments` are relative to spec/ (e.g. ["integration", "read"]).
  def categorized_placement_error(constant, dir_segments)
    category, *rest = dir_segments
    return "#{constant} must live under one of #{CATEGORIES.join("/")}/, not the spec root" if category.nil?
    return "#{constant}: #{category.inspect} is not a category (expected #{CATEGORIES.join("/")})" unless CATEGORIES.include?(category)

    inner = placement_error(constant, rest)
    return nil if inner.nil?

    # Re-anchor the inner message under the category for a legible hint.
    inner.sub("spec/", "spec/#{category}/").sub("the spec root", "spec/#{category}/")
  end
end
