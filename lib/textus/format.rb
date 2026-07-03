module Textus
  module Format
    def self.for(format) = Protocol::Format.for(format)
    def self.infer_from_extension(ext) = Protocol::Format.infer_from_extension(ext)
    def self.formats = Protocol::Format.formats
    def self.parse(...) = Protocol::Format.parse(...)
    def self.serialize(...) = Protocol::Format.serialize(...)
    def self.data_to_payload(...) = Protocol::Format.data_to_payload(...)
  end
end
