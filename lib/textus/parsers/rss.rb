require "rexml/document"
Textus::Parsers.register("rss", ->(content) {
  doc = REXML::Document.new(content)
  doc.elements.to_a("//item").map do |item|
    {
      "title" => item.elements["title"]&.text,
      "link"  => item.elements["link"]&.text,
      "pubDate" => item.elements["pubDate"]&.text,
    }
  end
})
