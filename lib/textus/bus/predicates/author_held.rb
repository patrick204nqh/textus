module Textus
  module Bus
    module Predicates
      class AuthorHeld
        def initialize(manifest)
          @manifest = manifest
        end

        def call(command, call)
          holders = @manifest.policy.roles_with_capability("author")
          return if holders.include?(call.role.to_s)

          if holders.empty?
            raise Textus::GuardFailed.new([["author_held", "no role holds the 'author' capability"]])
          end

          raise Textus::WriteForbidden.new(
            command.respond_to?(:key) ? command.key : "?",
            "?",
            verb: "author",
            holders: holders,
          )
        end
      end
    end
  end
end
