# frozen_string_literal: true

module Textus
  module Background
    module Job
      class Base
        def self.inherited(subclass)
          super
          Textus::Background::Job.registry << subclass if subclass.name
        end

        def call(**)
          raise NotImplementedError.new("#{self.class}#call")
        end

        def args = {}
      end
    end
  end
end
