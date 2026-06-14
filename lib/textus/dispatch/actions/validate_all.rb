# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class ValidateAll < Base
        extend Textus::Contract::DSL

        verb :validate_all
        summary "Internal store-wide schema + role-authority validation; backs doctor's " \
                "schema_violations check. No public surface (ADR 0105)."

        BURN = :sync

        def args
          {}
        end

        def call(container:, call:)
          manifest = container.manifest
          schemas = container.schemas
          audit_log = container.audit_log

          validator = Validator.new(
            reader: lambda do |key, ctnr, c|
              Textus::Dispatch::Actions::Get.new(key: key).call(container: ctnr, call: c)
            end,
            manifest: manifest,
            audit_log: audit_log,
            schema_for: ->(name) { schemas.fetch_or_nil(name) },
          )
          validator.call(container: container, call: call)
        end

        class Validator
          def initialize(reader:, manifest:, audit_log:, schema_for:)
            super()
            @reader = reader
            @manifest = manifest
            @audit_log = audit_log
            @schema_for = schema_for
          end

          def call(container:, call:)
            @container = container
            @call = call
            violations = []
            check_content_violations(violations)
            check_role_authority_violations(violations)
            { "protocol" => PROTOCOL, "ok" => violations.empty?, "violations" => violations }
          end

          private

          def check_content_violations(violations)
            @manifest.resolver.enumerate.each do |row|
              key = row[:key]
              mentry = row[:manifest_entry]
              env = fetch_envelope(key, violations) or next
              schema = mentry.schema && @schema_for.call(mentry.schema)
              next unless schema

              begin
                validate_schema!(schema, env, mentry.format)
              rescue Textus::Error => e
                violations << { "key" => key, "code" => e.code, "message" => e.message }
              end
            end
          end

          def check_role_authority_violations(violations)
            @manifest.resolver.enumerate.each do |row|
              mentry = row[:manifest_entry]
              next unless mentry.schema

              schema = @schema_for.call(mentry.schema)
              next unless schema

              env = begin
                @reader.call(row[:key], @container, @call)
              rescue StandardError
                next
              end
              append_authority_violations(violations, row[:key], env, schema)
            end
          end

          def append_authority_violations(violations, key, env, schema)
            last_writer = @audit_log.last_writer_for(key)
            return if last_writer.nil?

            last_writer_is_authority = @manifest.policy.roles_with_capability("author").include?(last_writer)

            env.meta.each_key do |field|
              owner = schema.maintained_by(field)
              next if owner.nil? || last_writer == owner || last_writer_is_authority

              violations << {
                "key" => key,
                "code" => "role_authority",
                "field" => field,
                "expected" => owner,
                "last_writer" => last_writer,
              }
            end
          end

          def fetch_envelope(key, violations)
            @reader.call(key, @container, @call)
          rescue Textus::Error => e
            violations << { "key" => key, "code" => e.code, "message" => e.message }
            nil
          end

          def validate_schema!(schema, envelope, format)
            payload = case format
                      when "json", "yaml"
                        envelope.content || {}
                      else
                        envelope.meta || {}
                      end
            schema.validate!(payload)
          end
        end
      end
    end
  end
end
