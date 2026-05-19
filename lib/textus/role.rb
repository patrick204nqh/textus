module Textus
  module Role
    PATTERN = /\A[a-z][a-z0-9_-]*\z/
    DEFAULT = "human".freeze

    def self.resolve(flag: nil, env: ENV, root:)
      candidate = flag || env["TEXTUS_ROLE"] || read_file(root) || DEFAULT
      raise InvalidRole.new(candidate) unless candidate.match?(PATTERN)
      candidate
    end

    def self.read_file(root)
      path = File.join(root, "role")
      return nil unless File.exist?(path)
      File.read(path).strip.then { |s| s.empty? ? nil : s }
    end
  end
end
