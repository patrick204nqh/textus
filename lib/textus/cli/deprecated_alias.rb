module Textus
  class CLI
    module DeprecatedAliasMixin
      def self.prepended(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def deprecated_name
          raise NotImplementedError.new("#{self}.deprecated_name must be defined")
        end

        def replacement_path
          raise NotImplementedError.new("#{self}.replacement_path must be defined")
        end
      end

      attr_writer :deprecated_alias

      def call(store)
        if @deprecated_alias
          @stderr.puts(
            "textus: '#{self.class.deprecated_name}' is deprecated; " \
            "use 'textus #{self.class.replacement_path}' instead. Removed in 0.6.",
          )
        end
        super
      end
    end
  end
end
