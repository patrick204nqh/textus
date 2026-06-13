# frozen_string_literal: true

require "json"
require "yaml"

module Textus
  module Step
    module Builtin
      class JsonFetch < Step::Fetch
        step_name "json"
        def call(config:, args:, **)
          _ = args
          { _meta: {}, body: YAML.dump(JSON.parse(config["bytes"].to_s)) }
        end
      end
    end
  end
end
