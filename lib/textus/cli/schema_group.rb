module Textus
  class CLI
    class SchemaGroup < Group
      self.cli_name = "schema"
      subcommands["show"]    = SchemaVerb
      subcommands["init"]    = SchemaInit
      subcommands["diff"]    = SchemaDiff
      subcommands["migrate"] = SchemaMigrate

      # Back-compat: `textus schema KEY` (dotted key, no subcommand word).
      # If the first positional looks like a dotted key, treat it as `schema show KEY`.
      def parse(argv)
        first = argv.first
        if first && dotted_key?(first)
          @stderr.puts(
            "textus: 'schema KEY' is deprecated; use 'textus schema show KEY' instead. Removed in 0.6.",
          )
          argv.unshift("show")
        end
        super
      end

      private

      def dotted_key?(token)
        return false if token.start_with?("-")
        return false unless token.include?(".")

        token.split(".").all? { |seg| seg.match?(Manifest::KEY_SEGMENT) }
      end
    end
  end
end
