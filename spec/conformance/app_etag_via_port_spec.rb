# frozen_string_literal: true

# Guard spec (ADR 0048 D4): application use cases under read/ and write/ must
# compute etags through the FileStore port (container.file_store.etag), never by
# calling Etag.for_file directly. The port (ports/storage/file_store.rb) and the
# Etag helper itself are the sanctioned homes; the envelope persist pipeline
# (envelope/io/writer.rb) is adjacent to the port and out of this guard's scope.
APP_ETAG_GLOBS = [
  File.expand_path("../../lib/textus/read/**/*.rb", __dir__),
  File.expand_path("../../lib/textus/write/**/*.rb", __dir__),
].freeze

DIRECT_ETAG_CALL = /\bEtag\.for_file\b/

RSpec.describe "Application use cases compute etags through the port (ADR 0048 D4)" do
  let(:app_files) { APP_ETAG_GLOBS.flat_map { |g| Dir.glob(g) } }

  it "finds app files (guard against a silent empty glob)" do
    expect(app_files).not_to be_empty
  end

  it "never calls Etag.for_file directly in read/ or write/" do
    violations = []
    app_files.each do |path|
      File.readlines(path, encoding: "utf-8").each_with_index do |line, idx|
        code = line.gsub(/#.*$/, "") # strip line comments
        next unless code.match?(DIRECT_ETAG_CALL)

        violations << "#{path}:#{idx + 1}: #{line.rstrip}"
      end
    end

    expect(violations).to be_empty,
                          "Direct Etag.for_file in an application use case — " \
                          "use container.file_store.etag(path):\n\n#{violations.join("\n")}"
  end
end
