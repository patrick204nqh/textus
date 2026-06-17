# frozen_string_literal: true

require "erb"

module Textus
  module Produce
    class Render
      def initialize(template_loader:)
        @template_loader = template_loader
      end

      def bytes_for(target:, data:, boot:)
        raise ArgumentError.new("Produce::Render called for a verbatim target #{target.to.inspect}") unless target.renders?

        ctx = target.inject_boot ? data.merge("boot" => boot) : data
        ERB.new(@template_loader.call(target.template), trim_mode: "-").result_with_hash(ctx)
      end
    end
  end
end
