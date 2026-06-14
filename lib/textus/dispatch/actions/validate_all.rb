# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class ValidateAll < Base
        extend Textus::Contract::DSL

        verb :validate_all
        summary "Store-wide schema + role-authority validation; backs doctor's schema_violations check."

        BURN = :sync

        def args
          {}
        end

        def call(container:, call:)
          Textus::Doctor::Validator.new(
            reader: ->(key, ctnr, c) { Textus::Dispatch::Actions::Get.new(key: key).call(container: ctnr, call: c) },
            manifest: container.manifest,
            audit_log: container.audit_log,
            schema_for: ->(name) { container.schemas.fetch_or_nil(name) },
          ).call(container: container, call: call)
        end
      end
    end
  end
end
