require "digest"

module Textus
  module Value
    module Etag
    def self.for_bytes(bytes)
      "sha256:#{Digest::SHA256.hexdigest(bytes)}"
    end

    def self.for_file(path)
      for_bytes(File.binread(path))
    end

    # The fingerprint of everything an agent's boot orientation depends on:
    # the manifest PLUS the executable contract — hooks and schemas. A
    # mid-session edit to any of these makes the cached orientation stale, so
    # the session must re-boot (ADR 0074). The composite is one digest over the
    # sorted per-file listing, so it is order-stable.
    def self.for_contract(root)
      listing = contract_files(root).map do |path|
        rel = path.delete_prefix(root).delete_prefix("/")
        "#{rel}:#{for_file(path)}"
      end.join("\n")
      for_bytes(listing)
    end

    # manifest.yaml, then every hook and schema file. Dir.glob already returns
    # sorted paths (Ruby 3.0+), keeping the digest independent of FS order.
    def self.contract_files(root)
      [
        File.join(root, "manifest.yaml"),
        *Dir.glob(File.join(root, "hooks", "**", "*.rb")),
        *Dir.glob(File.join(root, "schemas", "**", "*")).select { |f| File.file?(f) },
      ]
    end
  end
  end
end
