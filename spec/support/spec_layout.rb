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
  # Textus:: constant. Returns e.g. "Textus::Ports::BuildLock", or nil when the
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
  # (`describe Textus::Ports::BuildLock`) MUST sit under spec/ports/.
  def placement_error(constant, dir_segments)
    full = constant.split("::")[1..].map { |s| normalize(s) } # drop "Textus"
    dir  = dir_segments.map { |s| normalize(s) }

    return nil if dir == full[0, dir.length] && dir.length >= full.length - 1

    namespace = full[0, full.length - 1]
    expected  = namespace.empty? ? "the spec root" : "spec/#{namespace.join("/")}/"
    actual    = dir.empty? ? "the spec root" : "spec/#{dir.join("/")}/"
    "#{constant} should live under #{expected} (or spec/#{full.join("/")}/), not #{actual}"
  end

  # ── Category-aware mirror (the post-Phase-1 rule) ─────────────────────────
  #
  # The restructure moves every spec under one of these top-level category
  # dirs; the lib/-mirror then applies BELOW the category segment. This logic
  # is written ahead of the move (with its own unit examples) and only becomes
  # the live sweep rule once the files have moved.
  CATEGORIES = %w[unit integration conformance].freeze

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
