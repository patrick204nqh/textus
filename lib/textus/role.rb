module Textus
  module Role
    PATTERN = /\A[a-z][a-z0-9_-]*\z/
    DEFAULT = "human".freeze
    # The default acting identity for the MCP transport (ADR 0040): an agent
    # over stdio proposes; it does not inherit the human's authority. CLI
    # callers keep the `human` DEFAULT.
    AGENT = "agent".freeze

    def self.resolve(root:, flag: nil, env: ENV, default: DEFAULT)
      candidate = flag || env["TEXTUS_ROLE"] || read_file(root) || default
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
