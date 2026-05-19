Textus::Parsers.register("markdown-links", ->(content) {
  content.scan(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/).map do |text, href|
    { "text" => text, "href" => href }
  end
})
