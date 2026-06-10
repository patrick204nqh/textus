# frozen_string_literal: true

require "csv"
require "yaml"

module Textus
  module Step
    module Builtin
      class CsvFetch < Step::Fetch
        step_name "csv"
        def call(config:, args:, **)
          _ = args
          rows = CSV.parse(config["bytes"].to_s, headers: true).map(&:to_h)
          { _meta: {}, body: YAML.dump(rows) }
        end
      end
    end
  end
end
