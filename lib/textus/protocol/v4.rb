module Textus
  module Protocol
    module V4
      LANES = {
        "knowledge" => { writers: %w[human],
                         desc: "the maintained source of truth about the repo",
                         retention_ttl: nil },
        "scratchpad" => { writers: %w[agent],
                          desc: "the agent's own durable scratchpad (working memory)",
                          retention_ttl: nil },
        "artifacts" => { writers: %w[automation],
                         desc: "machine-maintained computed outputs",
                         retention_ttl: 3600 * 24 * 30 },
        "raw" => { writers: %w[human agent automation],
                   desc: "ingested external source material (write-once)",
                   retention_ttl: nil },
      }.freeze

      NAMING_PATTERNS = {
        "sequential" => /\A\d{4}-[a-z0-9-]+\.\w+\z/,
        "dated" => /\A\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.\w+\z/,
      }.freeze
    end
  end
end
