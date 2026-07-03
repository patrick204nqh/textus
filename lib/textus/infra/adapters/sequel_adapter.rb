# frozen_string_literal: true

require "sequel"

module Textus
  module Infra
    module Adapters
      class SequelAdapter
        def connect(path)
          Sequel.sqlite(path)
        end
      end
    end
  end
end
