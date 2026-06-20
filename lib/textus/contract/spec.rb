module Textus
  module Contract
    Spec = Data.define(:verb, :summary, :args, :surfaces, :views, :cli, :around, :cli_stdin) do
      def mcp? = surfaces.include?(:mcp)
      def cli? = surfaces.include?(:cli)

      def view(surface = :default) = views[surface] || views.fetch(:default)
      def cli_path = cli || verb.to_s
      def cli_words = cli_path.split
      def cli_group = cli_words.size > 1 ? cli_words.first : nil
      def cli_leaf  = cli_words.last

      def required_args = args.select(&:required)

      def input_schema
        props = args.to_h do |a|
          h = { "type" => Contract.json_type(a.type) }
          h["description"] = a.description if a.description
          [a.wire.to_s, h]
        end
        { type: "object", properties: props, required: required_args.map { |a| a.wire.to_s } }
      end
    end
  end
end
