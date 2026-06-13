# frozen_string_literal: true

module Textus
  module Step
    class Base
      class << self
        # The step kind — set once per kind subclass. Drives discovery and
        # which registry table the step lands in.
        def kind = raise NotImplementedError.new("#{self} must define .kind")

        # Required #call kwargs the loader validates against the subclass.
        def required_kwargs = []

        # Built-ins (and only built-ins) override the registered name when the
        # Ruby class name can't carry it (e.g. "markdown-links").
        def step_name(value = :__read__)
          if value == :__read__
            @step_name
          else
            @step_name = value.to_s
          end
        end
      end

      # Assigned by the loader/registry at registration time.
      attr_accessor :name
    end
  end
end
