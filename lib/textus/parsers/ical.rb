Textus::Parsers.register("ical-events", ->(content) {
  events = []
  current = nil
  content.each_line do |line|
    line = line.strip
    case line
    when "BEGIN:VEVENT" then current = {}
    when "END:VEVENT"   then events << current; current = nil
    when /\A(SUMMARY|DTSTART|DTEND|UID|LOCATION|DESCRIPTION):(.*)\z/
      current[$1.downcase] = $2 if current
    end
  end
  events
})
