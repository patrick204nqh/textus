module Textus
  module Protocol
    module V4
      LANES = {
        "knowledge"  => { writers: %w[human],
                           desc: "the maintained source of truth about the repo" },
        "scratchpad" => { writers: %w[agent],
                           desc: "the agent's own durable scratchpad (working memory)" },
        "proposals"  => { writers: %w[human agent],
                           desc: "changes awaiting a human accept" },
        "artifacts"  => { writers: %w[automation],
                           desc: "machine-maintained computed outputs" },
        "raw"        => { writers: %w[human agent automation],
                           desc: "ingested external source material (write-once)" },
      }.freeze

      NAMING_PATTERNS = {
        "sequential" => /\A\d{4}-[a-z0-9-]+\.\w+\z/,
        "dated"      => /\A\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.\w+\z/,
      }.freeze
    end
  end
end
