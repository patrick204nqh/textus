# frozen_string_literal: true

require "sequel"

module Textus
  module DependencyAdapters
    class SequelAdapter
      def connect(path)
        Sequel.sqlite(path)
      end
    end
  end
end
