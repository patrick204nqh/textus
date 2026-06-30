# frozen_string_literal: true

require "erb"
require_relative "../links/resolver"
require_relative "../links/uri_rewriter"
require_relative "render/context"

module Textus
  module Produce
    class Render
      def initialize(template_loader:, manifest: nil, source_publish_path: nil, entry_key: nil, edge_store: nil)
        @template_loader     = template_loader
        @manifest            = manifest
        @source_publish_path = source_publish_path
        @entry_key           = entry_key
        @edge_store          = edge_store
      end

      def bytes_for(target:, data:, boot:)
        raise ArgumentError.new("Produce::Render called for a verbatim target #{target.to.inspect}") unless target.renders?

        locals   = target.inject_boot ? data.merge("boot" => boot) : data
        resolver = @manifest ? Textus::Links::Resolver.new(manifest: @manifest) : nil
        ctx      = Render::Context.for(locals: locals, resolver: resolver, from_path: target.to)
        raw      = ERB.new(@template_loader.call(target.template), trim_mode: "-").result(ctx.binding)
        rewrite(raw, target.to, resolver)
      end

      private

      def rewrite(bytes, from_path, resolver)
        return bytes unless resolver && bytes.include?("textus:")

        Textus::Links::UriRewriter.new(
          resolver: resolver,
          from_path: from_path,
          from_key: @entry_key,
          edge_store: @edge_store,
        ).rewrite(bytes)
      end
    end
  end
end
