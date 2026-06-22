module Textus
  module Jobs
    def self.fetch(type)
      Store::Jobs::Registry.fetch(type)
    rescue Store::Jobs::Registry::UnknownJob
      raise Textus::UsageError.new("unknown job type: #{type}")
    end
  end
end
