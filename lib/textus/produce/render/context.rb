# frozen_string_literal: true

module Textus
  module Produce
    class Render
      class Context
        def self.for(locals:, resolver: nil, from_path: nil, from_key: nil, edge_store: nil)
          new(locals, resolver, from_path, from_key, edge_store)
        end

        def initialize(locals, resolver, from_path, from_key, edge_store)
          @locals     = locals
          @resolver   = resolver
          @from_path  = from_path
          @from_key   = from_key
          @edge_store = edge_store
        end

        def to_erb_binding
          mod = Module.new
          @locals.each { |k, v| mod.define_method(k.to_sym) { v } }
          obj = Object.new.extend(mod)

          if @resolver && @from_path
            resolver   = @resolver
            from_path  = @from_path
            from_key   = @from_key
            edge_store = @edge_store
            obj.define_singleton_method(:textus_link) do |key|
              resolved = resolver.resolve(key: key, from_path: from_path)
              edge_store&.record(from_key: from_key, to_key: key)
              resolved
            rescue Textus::Links::Resolver::UnknownKeyError
              "`textus get #{key}`"
            end
          end

          obj.instance_eval { binding }
        end
      end
    end
  end
end
