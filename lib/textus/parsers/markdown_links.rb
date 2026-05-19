Textus::Parsers.register("markdown-links", lambda { |content|
  content.scan(%r{\[([^\]]+)\]\((https?://[^)\s]+)\)}).map do |text, href|
    { "text" => text, "href" => href }
  end
})
