# frozen_string_literal: true

# Guard spec: enforces that lib/textus/domain/ performs no direct filesystem or
# wall-clock I/O.  All disk and clock access must be routed through injected
# ports (FileStat, Clock).
#
# Allowed in domain (NOT considered I/O):
#   - Pure path math: File.join, File.dirname, File.basename, File.expand_path,
#     File.absolute_path?, File.split, File.extname, File::SEPARATOR
#   - Pure compute: Digest (hashing injected bytes)
#   - Time.parse (parsing a stored timestamp string, not reading the wall clock)
#
# Forbidden (must never appear in domain source):
#   - Any File.<method> NOT in ALLOWED_FILE_METHODS (e.g. File.read, File.open,
#     File.exist?, File.readlines, File.foreach, File.stat, File.new, ...)
#   - IO.* (use an injected port)
#   - FileUtils.*
#   - Dir.* and Dir[...] (use an injected FileStat port)
#   - Pathname (use plain string paths)
#   - Shell execution: backticks or %x{...}
#   - bare open(...) (Kernel#open — filesystem/network)
#   - Time.now / Time.new (wall-clock; use an injected Clock port)
#
# NOTE on comment stripping: line comments are stripped before matching so that
# prose like "FileStat replaces File.read" in a comment does not trip the guard.
# The minor false-negative of `#{}` interpolation containing I/O calls is
# acceptable — the domain does not use that pattern.

DOMAIN_PURITY_GLOB = File.expand_path("../../lib/textus/domain/**/*.rb", __dir__)

# Pure path-math methods allowed on File.*. Everything else is I/O.
ALLOWED_FILE_METHODS = %w[
  join
  dirname
  basename
  expand_path
  absolute_path?
  split
  extname
].freeze

# Simple regex-based forbidden patterns (applied after comment stripping).
DOMAIN_PURITY_FORBIDDEN_PATTERNS = [
  [/\bIO\.[a-z]/,
   "IO.* (use an injected port instead)"],
  [/\bFileUtils\b/,
   "FileUtils (use an injected port instead)"],
  [/\bDir[.\[]/,
   "Dir.* / Dir[...] (use an injected FileStat port instead)"],
  [/\bPathname\b/,
   "Pathname (use plain string paths; access via an injected port)"],
  [/`/,
   "backtick shell execution (forbidden in domain)"],
  [/%x./,
   "%x shell execution (forbidden in domain)"],
  [/(?<![.\w])open\s*\(/,
   "bare open(...) / Kernel#open (use an injected port instead)"],
  [/\bTime\.now\b/,
   "Time.now wall-clock read (use an injected Clock port instead)"],
  [/\bTime\.new\b/,
   "Time.new wall-clock read (use an injected Clock port instead)"],
].freeze

RSpec.describe "Domain purity — no direct filesystem/clock I/O" do
  let(:domain_files) { Dir.glob(DOMAIN_PURITY_GLOB) }

  it "finds at least one domain file (guard against a silent empty glob)" do
    expect(domain_files).not_to be_empty
  end

  it "contains no forbidden I/O calls in any domain file" do
    violations = []

    domain_files.each do |path|
      source_lines = File.readlines(path, encoding: "utf-8")

      source_lines.each_with_index do |line, idx|
        # Strip Ruby line comments before matching so that prose in comments
        # (e.g. "FileStat substitute for File.file?") does not trip the guard.
        code = line.gsub(/#.*$/, "")

        # --- File.* allowlist check (two-step: scan then filter) ---
        # Scan for every File.<method> call; flag any method not in the
        # allowed pure-path-math set. This is more reliable than a
        # negative-lookahead regex (avoids `\b`-after-`?` pitfalls).
        code.scan(/\bFile\.([a-zA-Z_]+[?!]?)/) do |m|
          method_name = m[0]
          next if ALLOWED_FILE_METHODS.include?(method_name)

          violations << "#{path}:#{idx + 1}: File.#{method_name} is not a " \
                        "pure path-math method (use an injected FileStat port instead)\n" \
                        "  #{line.rstrip}" # rubocop:disable Layout/LineContinuationLeadingSpace
        end

        # --- Regex-based forbidden pattern checks ---
        # Strip string literals first so backtick-quoted prose inside an error
        # message (e.g. "the `to:` field") does not read as shell execution; the
        # guard targets real I/O calls, never message punctuation.
        code_no_strings = code.gsub(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/, '""')
        DOMAIN_PURITY_FORBIDDEN_PATTERNS.each do |pattern, explanation|
          next unless code_no_strings.match?(pattern)

          violations << "#{path}:#{idx + 1}: #{explanation}\n  #{line.rstrip}"
        end
      end
    end

    expect(violations).to be_empty,
                          "Domain purity violated — route I/O through injected ports:\n\n" \
                          "#{violations.join("\n\n")}"
  end
end
