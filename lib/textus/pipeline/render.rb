require "mustache"

module Textus
  module Pipeline
    # Renders an entry's stored DATA into the bytes for one publish target
    # (ADR 0094). Relocates the Mustache logic that used to live in the
    # build-time Markdown renderer. Provenance is NOT added here — it lives in
    # the data's `_meta`; a template surfaces it if the output should show it.
    # A verbatim target (no template) is the caller's job to copy.
    class Render
      def initialize(template_loader:)
        @template_loader = template_loader
      end

      # target: a rendering Policy::PublishTarget. data: parsed entry data.
      # boot:   boot context hash or nil. Returns the rendered String.
      def bytes_for(target:, data:, boot:)
        raise ArgumentError.new("Produce::Render called for a verbatim target #{target.to.inspect}") unless target.renders?

        ctx = target.inject_boot ? data.merge("boot" => boot) : data
        Mustache.render(@template_loader.call(target.template), ctx)
      end
    end
  end
end
