require "digest"
require "json"

module Textus
  module Domain
    module Jobs
      # A unit of deferred work. Pure data. The id is `<type>:<digest>` where the
      # digest is over the args with sorted keys, so logically-identical enqueues
      # collide on the same id — which is how the Queue dedups (the file already
      # exists). At-least-once delivery means handlers must be idempotent.
      class Job
        DIGEST_BYTES = 16

        attr_reader :type, :args, :enqueued_by, :max_attempts
        attr_accessor :attempts, :last_error

        def initialize(type:, args:, enqueued_by: nil, attempts: 0, max_attempts: 3, last_error: nil)
          @type = type.to_s
          @args = stringify(args)
          @enqueued_by = enqueued_by
          @attempts = attempts
          @max_attempts = max_attempts
          @last_error = last_error
        end

        def id
          "#{@type}:#{digest}"
        end

        def to_h
          {
            "type" => @type, "args" => @args, "enqueued_by" => @enqueued_by,
            "attempts" => @attempts, "max_attempts" => @max_attempts, "last_error" => @last_error
          }
        end

        def self.from_h(hash)
          new(
            type: hash["type"], args: hash["args"] || {}, enqueued_by: hash["enqueued_by"],
            attempts: hash["attempts"] || 0, max_attempts: hash["max_attempts"] || 3,
            last_error: hash["last_error"]
          )
        end

        private

        def digest
          canonical = JSON.dump(@args.sort.to_h)
          Digest::SHA256.hexdigest(canonical)[0, DIGEST_BYTES]
        end

        def stringify(hash)
          hash.transform_keys(&:to_s)
        end
      end
    end
  end
end
