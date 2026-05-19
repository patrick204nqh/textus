Textus::Parsers.register("ical-events", lambda { |content|
  events = []
  current = nil
  content.each_line do |line|
    line = line.strip
    case line
    when "BEGIN:VEVENT" then current = {}
    when "END:VEVENT"   then events << current
                             current = nil
    when /\A(SUMMARY|DTSTART|DTEND|UID|LOCATION|DESCRIPTION):(.*)\z/
      current[Regexp.last_match(1).downcase] = Regexp.last_match(2) if current
    end
  end
  events
})
