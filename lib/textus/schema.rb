require "yaml"

module Textus
  class Schema
    attr_reader :name, :required, :optional, :fields, :raw

    def self.load(path)
      Protocol::Schema.load(path)
    end

    def initialize(raw)
      @impl = Protocol::Schema.new(raw)
      @raw = @impl.raw
      @name = @impl.name
      @required = @impl.required
      @optional = @impl.optional
      @fields = @impl.fields
    end

    def to_h = @impl.to_h
    def maintained_by(field) = @impl.maintained_by(field)
    def unowned_fields = @impl.unowned_fields
    def evolution = @impl.evolution
    def validate!(frontmatter) = @impl.validate!(frontmatter)
  end
end
