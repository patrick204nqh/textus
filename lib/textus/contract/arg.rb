module Textus
  module Contract
    Arg = Data.define(
      :name, :type, :required, :positional, :session_default,
      :description, :wire_name, :default, :source, :coerce, :cli_default
    ) do
      def wire = wire_name || name
    end
  end
end
