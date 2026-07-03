module Textus
  module VerbRegistry
    TYPE_MAP = {
      String => "string", Integer => "integer", Hash => "object",
      Array => "array", :boolean => "boolean"
    }.freeze

    VerbSpec = Data.define(:verb, :summary, :args, :surfaces, :views, :cli, :cli_stdin, :category) do
      def mcp? = surfaces.include?(:mcp)
      def cli? = surfaces.include?(:cli)
      def view(surface = :default) = views[surface] || views.fetch(:default)
      def cli_path = cli || verb.to_s
      def cli_words = cli_path.split
      def cli_group = cli_words.size > 1 ? cli_words.first : nil
      def cli_leaf  = cli_words.last
      def required_args = args.select(&:required)
      def read? = category == :read
      def write? = category == :write
      def maintenance? = category == :maintenance

      def input_schema
        props = args.to_h do |a|
          json_type = VerbRegistry::TYPE_MAP[a.type] || "string"
          h = { "type" => json_type }
          h["description"] = a.description if a.description
          [a.wire.to_s, h]
        end
        { type: "object", properties: props, required: required_args.map { |a| a.wire.to_s } }
      end
    end
  end
end
