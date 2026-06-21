module Textus
  class Store
    module Jobs
      module Registry
        class UnknownJob < KeyError; end

        JOBS = {
          "index"       => Store::Jobs::Index,
          "materialize" => Store::Jobs::Materialize,
          "sweep"       => Store::Jobs::Sweep,
        }.freeze

        def self.fetch(type)
          JOBS.fetch(type.to_s) { raise UnknownJob, "Unknown job type: #{type}" }
        end
      end
    end
  end
end
