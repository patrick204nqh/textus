module Textus
  class Manifest
    class Entry
      class Derived < Base
        Projection = Data.define(:select, :pluck, :sort_by, :transform)
        External   = Data.define(:sources, :runner)

        attr_reader :source, :template, :inject_boot, :events

        def initialize(source:, template: nil, inject_boot: false, events: {}, **rest)
          super(**rest)
          @source = source
          @template = template
          @inject_boot = inject_boot
          @events = events || {}
        end

        def derived? = true
        def projection? = @source.is_a?(Projection)
        def external?   = @source.is_a?(External)
      end
    end
  end
end
