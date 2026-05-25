module Textus
  module Role
    PATTERN = /\A[a-z][a-z0-9_-]*\z/
    DEFAULT = "human".freeze

    LEGACY_RENAMES = {
      "ai" => "agent",
      "script" => "runner",
      "build" => "builder",
    }.freeze

    def self.resolve(root:, flag: nil, env: ENV)
      candidate = flag || env["TEXTUS_ROLE"] || read_file(root) || DEFAULT

      if (new_name = LEGACY_RENAMES[candidate])
        raise InvalidRole.new(
          candidate,
          message: "#{candidate}: legacy role renamed to '#{new_name}' in textus/3. " \
                   "Run `textus migrate --to=textus/3` or pass --as=#{new_name}.",
        )
      end

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
