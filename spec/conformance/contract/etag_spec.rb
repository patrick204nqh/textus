require "spec_helper"

# Guard spec (ADR 0048 D4): application use cases under read/ and write/ must
# compute etags through the FileStore port (container.file_store.etag), never by
# calling Etag.for_file directly. The port (ports/storage/file_store.rb) and the
# Etag helper itself are the sanctioned homes; the envelope persist pipeline
# (envelope/io/writer.rb) is adjacent to the port and out of this guard's scope.
ETAG_SPEC_APP_GLOBS = [
  File.expand_path("../../../lib/textus/action/**/*.rb", __dir__),
].freeze
ETAG_SPEC_DIRECT_CALL = /\bEtag\.for_file\b/

# Guard spec (Finding 2 of the 2026-05-29 architecture review): the manifest
# etag — and any other etag — must be computed through the FileStore port
# (Etag.for_file / FileStore#etag), never by hand-rolling
# `Digest::SHA256.hexdigest(File.read(...))` in application or interface code.
# Etag.for_bytes itself (lib/textus/etag.rb) is the single sanctioned home for
# the digest and is exempt.
ETAG_SPEC_LIB_GLOB = File.expand_path("../../../lib/textus/**/*.rb", __dir__)
ETAG_SPEC_HELPER = File.expand_path("../../../lib/textus/etag.rb", __dir__)
# SentinelStore stores a raw sha256 for target-file integrity comparison (not
# an etag), predates this guard, and is exempt.
ETAG_SPEC_SENTINEL_STORE = File.expand_path("../../../lib/textus/ports/sentinel_store.rb", __dir__)
ETAG_SPEC_EXEMPT_FILES = [ETAG_SPEC_HELPER, ETAG_SPEC_SENTINEL_STORE].freeze
# Matches a SHA256 digest taken directly over a freshly-read file.
ETAG_SPEC_HANDROLLED = /Digest::SHA256\.hexdigest\(\s*File\.(?:read|binread)/

RSpec.describe "Textus::Etag.for_contract" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "hooks"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), "version: textus/4\n")
    File.write(File.join(root, "hooks/a.rb"), "Textus.hook { |reg| }\n")
    File.write(File.join(root, "schemas/x.yaml"), "type: object\n")
  end

  after { FileUtils.remove_entry(tmp) }

  def etag = Textus::Etag.for_contract(root)

  it "produces a stable sha256-prefixed digest" do
    expect(etag).to start_with("sha256:")
    expect(etag).to eq(Textus::Etag.for_contract(root))
  end

  it "changes when the manifest changes" do
    was = etag
    File.write(File.join(root, "manifest.yaml"), "version: textus/4\n# edit\n")
    expect(etag).not_to eq(was)
  end

  it "changes when a hook file changes" do
    was = etag
    File.write(File.join(root, "hooks/a.rb"), "Textus.hook { |reg| } # edit\n")
    expect(etag).not_to eq(was)
  end

  it "changes when a schema file changes" do
    was = etag
    File.write(File.join(root, "schemas/x.yaml"), "type: string\n")
    expect(etag).not_to eq(was)
  end

  it "changes when a new hook file is added" do
    was = etag
    File.write(File.join(root, "hooks/b.rb"), "Textus.hook { |reg| }\n")
    expect(etag).not_to eq(was)
  end

  # Guard spec (ADR 0048 D4): application actions under dispatch/actions/ must
  # compute etags through the FileStore port (container.file_store.etag), never by
  # calling Etag.for_file directly. The port (ports/storage/file_store.rb) and the
  # Etag helper itself are the sanctioned homes; the envelope persist pipeline
  # (envelope/io/writer.rb) is adjacent to the port and out of this guard's scope.
  describe "application use cases compute etags through the port (ADR 0048 D4)" do
    let(:app_files) { ETAG_SPEC_APP_GLOBS.flat_map { |g| Dir.glob(g) } }

    it "finds app files (guard against a silent empty glob)" do
      expect(app_files).not_to be_empty
    end

    it "never calls Etag.for_file directly in dispatch/actions/" do
      violations = []
      app_files.each do |path|
        File.readlines(path, encoding: "utf-8").each_with_index do |line, idx|
          code = line.gsub(/#.*$/, "") # strip line comments
          next unless code.match?(ETAG_SPEC_DIRECT_CALL)

          violations << "#{path}:#{idx + 1}: #{line.rstrip}"
        end
      end

      expect(violations).to be_empty,
                            "Direct Etag.for_file in an application use case — " \
                            "use container.file_store.etag(path):\n\n#{violations.join("\n")}"
    end
  end

  # Guard spec (Finding 2 of the 2026-05-29 architecture review): the manifest
  # etag — and any other etag — must be computed through the FileStore port
  # (Etag.for_file / FileStore#etag), never by hand-rolling
  # `Digest::SHA256.hexdigest(File.read(...))` in application or interface code.
  # Etag.for_bytes itself (lib/textus/etag.rb) is the single sanctioned home for
  # the digest and is exempt.
  describe "no hand-rolled manifest etag" do
    let(:lib_files) { Dir.glob(ETAG_SPEC_LIB_GLOB).reject { |f| ETAG_SPEC_EXEMPT_FILES.include?(f) } }

    it "finds lib files (guard against a silent empty glob)" do
      expect(lib_files).not_to be_empty
    end

    it "computes etags through the port, never Digest::SHA256.hexdigest(File.read(...))" do
      violations = []

      lib_files.each do |path|
        File.readlines(path, encoding: "utf-8").each_with_index do |line, idx|
          code = line.gsub(/#.*$/, "") # strip line comments
          next unless code.match?(ETAG_SPEC_HANDROLLED)

          violations << "#{path}:#{idx + 1}: #{line.rstrip}"
        end
      end

      expect(violations).to be_empty,
                            "Hand-rolled etag found — use FileStore#etag / Etag.for_file:\n\n" \
                            "#{violations.join("\n")}"
    end
  end
end
