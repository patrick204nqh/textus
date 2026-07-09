module Textus
  module Protocol
    module ActionRegistry
      TYPE_MAP = {
        String => "string", Integer => "integer", Hash => "object",
        Array => "array", :boolean => "boolean"
      }.freeze

      SYSTEM_ACTIONS = %i[boot audit blame pulse drain workflow_spec].to_set.freeze

      ActionSpec = Data.define(:action, :summary, :args, :surfaces, :category) do
        def initialize(action:, summary:, args:, surfaces:, category:, lane: nil)
          @lane = lane
          super(action:, summary:, args:, surfaces:, category:)
        end

        def lane = @lane
        def system? = SYSTEM_ACTIONS.include?(action)
        def mcp? = surfaces.include?(:mcp)
        def cli? = surfaces.include?(:cli)
        def cli_path = action.to_s.tr("_", " ")
        def cli_words = cli_path.split
        def cli_group = cli_words.size > 1 ? cli_words.first : nil
        def cli_leaf  = cli_words.last
        def required_args = args.select(&:required)
        def read? = category == :read
        def write? = category == :write
        def maintenance? = category == :maintenance

        def input_schema
          props = args.to_h do |a|
            json_type = ActionRegistry::TYPE_MAP[a.type] || "string"
            h = { "type" => json_type }
            h["description"] = a.description if a.description
            [a.wire.to_s, h]
          end
          { type: "object", properties: props, required: required_args.map { |a| a.wire.to_s } }
        end
      end
    end
  end
end
