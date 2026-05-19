Textus.fetcher(:lowercase) do |config:, store:|
  { frontmatter: {}, body: config["bytes"].to_s.downcase }
end
