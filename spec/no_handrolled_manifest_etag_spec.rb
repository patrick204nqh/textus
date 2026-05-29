# frozen_string_literal: true

# Guard spec (Finding 2 of the 2026-05-29 architecture review): the manifest
# etag — and any other etag — must be computed through the FileStore port
# (Etag.for_file / FileStore#etag), never by hand-rolling
# `Digest::SHA256.hexdigest(File.read(...))` in application or interface code.
# Etag.for_bytes itself (lib/textus/etag.rb) is the single sanctioned home for
# the digest and is exempt.

LIB_GLOB = File.expand_path("../lib/textus/**/*.rb", __dir__)
ETAG_HELPER = File.expand_path("../lib/textus/etag.rb", __dir__)
# SentinelStore stores a raw sha256 for target-file integrity comparison (not
# an etag), predates this guard, and is exempt.
SENTINEL_STORE = File.expand_path("../lib/textus/ports/sentinel_store.rb", __dir__)

EXEMPT_FILES = [ETAG_HELPER, SENTINEL_STORE].freeze

# Matches a SHA256 digest taken directly over a freshly-read file.
HANDROLLED_ETAG = /Digest::SHA256\.hexdigest\(\s*File\.(?:read|binread)/

RSpec.describe "No hand-rolled manifest etag" do
  let(:lib_files) { Dir.glob(LIB_GLOB).reject { |f| EXEMPT_FILES.include?(f) } }

  it "finds lib files (guard against a silent empty glob)" do
    expect(lib_files).not_to be_empty
  end

  it "computes etags through the port, never Digest::SHA256.hexdigest(File.read(...))" do
    violations = []

    lib_files.each do |path|
      File.readlines(path, encoding: "utf-8").each_with_index do |line, idx|
        code = line.gsub(/#.*$/, "") # strip line comments
        next unless code.match?(HANDROLLED_ETAG)

        violations << "#{path}:#{idx + 1}: #{line.rstrip}"
      end
    end

    expect(violations).to be_empty,
                          "Hand-rolled etag found — use FileStore#etag / Etag.for_file:\n\n" \
                          "#{violations.join("\n")}"
  end
end
