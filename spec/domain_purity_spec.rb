# frozen_string_literal: true

# Guard spec: enforces that lib/textus/domain/ performs no direct filesystem or
# wall-clock I/O.  All disk and clock access must be routed through injected
# ports (FileStat, Clock).
#
# Allowed in domain (NOT considered I/O):
#   - Pure path math: File.join, File.dirname, File.absolute_path?,
#     File.expand_path, File.basename, File::SEPARATOR
#   - Pure compute: Digest (hashing injected bytes)
#   - Time.parse (parsing a stored timestamp string, not reading the wall clock)
#
# Forbidden (must never appear in domain source):
#   - File.read, File.binread, File.write, File.exist?, File.mtime,
#     File.directory?, File.file?, File.open
#   - FileUtils.*
#   - Dir.* (Dir.glob, Dir.[], Dir.entries, etc.)
#   - Time.now

DOMAIN_PURITY_GLOB = File.expand_path("../lib/textus/domain/**/*.rb", __dir__)

DOMAIN_PURITY_FORBIDDEN = [
  [/\bFile\.(read|binread|write|exist\?|mtime|directory\?|file\?|open)\b/,
   "direct File I/O (use an injected FileStat port instead)"],
  [/\bFileUtils\b/,
   "FileUtils (use an injected port instead)"],
  [/\bDir\.\w/,
   "Dir.* (use an injected FileStat port instead)"],
  [/\bTime\.now\b/,
   "Time.now wall-clock read (use an injected Clock port instead)"],
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

        DOMAIN_PURITY_FORBIDDEN.each do |pattern, explanation|
          next unless code.match?(pattern)

          violations << "#{path}:#{idx + 1}: #{explanation}\n  #{line.rstrip}"
        end
      end
    end

    expect(violations).to be_empty,
                          "Domain purity violated — route I/O through injected ports:\n\n" \
                          "#{violations.join("\n\n")}"
  end
end
