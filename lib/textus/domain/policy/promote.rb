module Textus
  module Domain
    module Policy
      class Promote
        KNOWN = %i[schema_valid accept_signed].freeze
        attr_reader :requires

        def initialize(requires:)
          syms = Array(requires).map { |r| r.to_s.to_sym }
          unknown = syms - KNOWN
          unless unknown.empty?
            raise Textus::UsageError.new(
              "unknown promote requirement: #{unknown.first.inspect} (known: #{KNOWN.join(", ")})",
            )
          end

          @requires = syms
        end

        def demands?(req)
          @requires.include?(req)
        end
      end
    end
  end
end
