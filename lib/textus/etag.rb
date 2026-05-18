require "digest"

module Textus
  module Etag
    def self.for_bytes(bytes)
      "sha256:#{Digest::SHA256.hexdigest(bytes)}"
    end

    def self.for_file(path)
      for_bytes(File.binread(path))
    end
  end
end
