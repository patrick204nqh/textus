# frozen_string_literal: true

module Textus
  module Produce
    class Render
      class Context
        def self.for(locals:, resolver: nil, from_path: nil)
          new(locals, resolver, from_path)
        end

        def initialize(locals, resolver, from_path)
          @locals    = locals
          @resolver  = resolver
          @from_path = from_path
        end

        def binding
          mod = Module.new
          @locals.each { |k, v| mod.define_method(k.to_sym) { v } }
          obj = Object.new.extend(mod)

          if @resolver && @from_path
            resolver  = @resolver
            from_path = @from_path
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
end
