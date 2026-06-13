# frozen_string_literal: true

module Textus
  module Step
    class Signature
      def initialize(callable)
        @params = callable.parameters
      end

      def accepts_keyrest?
        @params.any? { |type, _| type == :keyrest }
      end

      def declared_keys
        @params.each_with_object([]) { |(t, n), acc| acc << n if %i[keyreq key].include?(t) }
      end

      def missing(required)
        return [] if accepts_keyrest?

        required - declared_keys
      end

      def filter(kwargs)
        return kwargs if accepts_keyrest?

        kwargs.slice(*declared_keys)
      end
    end
  end
end
