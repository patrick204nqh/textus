module Textus
  module Protocol
    Blueprint = Data.define(
      :key, :lane, :naming, :format, :schema,
      :key_grammar, :meta_template, :template
    ) do
      def initialize(**)
        super
        freeze
      end
    end
  end
end
