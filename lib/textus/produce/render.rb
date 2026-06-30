# frozen_string_literal: true

require "erb"
require_relative "../links/resolver"

module Textus
  module Produce
    class Render
      def initialize(template_loader:, manifest: nil, source_publish_path: nil)
        @template_loader      = template_loader
        @manifest             = manifest
        @source_publish_path  = source_publish_path
      end

      def bytes_for(target:, data:, boot:)
        raise ArgumentError.new("Produce::Render called for a verbatim target #{target.to.inspect}") unless target.renders?

        locals = target.inject_boot ? data.merge("boot" => boot) : data
        ctx    = build_context(locals, target.to)
        ERB.new(@template_loader.call(target.template), trim_mode: "-").result(ctx)
      end

      private

      # Build an ERB binding where each local is a method and textus_link is
      # available as a method (not a proc variable) so templates can call
      # <%= textus_link("key") %> naturally.
      def build_context(locals, from_path)
        resolver = @manifest ? Textus::Links::Resolver.new(manifest: @manifest) : nil

        mod = Module.new
        locals.each do |k, v|
          mod.define_method(k.to_sym) { v }
        end

        obj = Object.new.extend(mod)

        if resolver && from_path
          obj.define_singleton_method(:textus_link) do |key|
            resolver.resolve(key: key, from_path: from_path)
          rescue Textus::Links::Resolver::UnknownKeyError
            "`textus get #{key}`"
          end
        end

        obj.instance_eval { binding }
      end
    end
  end
end
