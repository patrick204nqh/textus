#!/usr/bin/env ruby
# frozen_string_literal: true

#
# One-off migration for textus 0.30.0 (mandatory zone kind).
# Injects an explicit `kind:` into every inline zone hash in spec fixtures
# that lacks one. Idempotent (re-running is a no-op). DELETE after use.
#
#   ruby scripts/migrate_zone_kinds.rb
#
# Rule (preserves the old derived_zone? answer):
#   - any writer is a generator role (builder/compiler/generator) => derived
#   - otherwise                                                    => origin
# Queue zones (proposal targets) are NOT auto-assigned here; they surface as
# red propose-routing specs in Task 3 and are set to `queue` by hand there.

GENERATOR = %w[builder compiler generator].freeze

# Matches `{ name: <zone>, ... write_policy: [<writers>] ...` up to the
# write_policy list. Does not cross into read_policy / closing brace, so the
# tail of the hash is left untouched by String#sub.
ZONE_RE = /(\{\s*name:\s*)([A-Za-z_][\w-]*)(\s*,\s*)(.*?write_policy:\s*\[([^\]]*)\])/

def kind_for(writers_csv)
  writers = writers_csv.split(",").map(&:strip)
  writers.any? { |w| GENERATOR.include?(w) } ? "derived" : "origin"
end

changed = 0
Dir.glob("spec/**/*.rb").each do |file|
  src = File.read(file)
  out = src.each_line.map do |line|
    next line unless line.include?("name:") && line.include?("write_policy:")
    next line if line.match?(/\bkind:/) # already has a kind — skip
    # Skip lines where the zone hash is inside a Ruby string literal
    # (e.g. YAML.safe_load("... { name: w, write_policy: [human] } ..."))
    next line if line.match?(/YAML\.safe_load\(["']/) || line.match?(/^\s*[^#]*["'].*\{.*name:.*write_policy:.*\}.*["']/)

    line.sub(ZONE_RE) do
      pre, name, sep, rest, writers = Regexp.last_match.captures
      "#{pre}#{name}#{sep}kind: #{kind_for(writers)}, #{rest}"
    end
  end.join
  next if out == src

  File.write(file, out)
  changed += 1
end
puts "rewrote #{changed} files"
