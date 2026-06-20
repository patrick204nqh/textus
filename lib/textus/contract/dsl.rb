module Textus
  module Contract
    module DSL
      def verb(name = nil)
        if name
          raise "contract already built; declare verb before reading .contract" if defined?(@__contract) && @__contract

          @__verb = name
        else
          @__verb
        end
      end

      def summary(text = nil)
        if text
          raise "contract already built; declare summary before reading .contract" if defined?(@__contract) && @__contract

          @__summary = text
        else
          @__summary
        end
      end

      def surfaces(*list)
        if list.empty?
          @__surfaces ||= []
        else
          raise "contract already built; declare surfaces before reading .contract" if defined?(@__contract) && @__contract

          @__surfaces = list
        end
      end

      def cli(path = nil)
        if path
          raise "contract already built; declare cli before reading .contract" if defined?(@__contract) && @__contract

          @__cli = path.to_s
        else
          @__cli
        end
      end

      def arg(name, type, required: false, positional: false, session_default: nil, description: nil, wire_name: nil, default: nil, source: nil, coerce: nil, cli_default: :__unset) # rubocop:disable Metrics/ParameterLists,Layout/LineLength
        raise "contract already built; declare args before reading .contract" if defined?(@__contract) && @__contract

        (@__args ||= []) << Arg.new(
          name: name, type: type, required: required,
          positional: positional, session_default: session_default,
          description: description, wire_name: wire_name, default: default,
          source: source, coerce: coerce, cli_default: cli_default
        )
      end

      def cli_stdin(mode = :__read)
        return @__cli_stdin if mode == :__read

        raise "contract already built; declare cli_stdin before reading .contract" if defined?(@__contract) && @__contract

        @__cli_stdin = mode
      end

      def view(surface = :default, &blk)
        return (@__views ||= {})[surface] unless blk

        raise "contract already built; declare view before reading .contract" if defined?(@__contract) && @__contract

        (@__views ||= {})[surface] = blk
      end

      def contract?
        !@__verb.nil?
      end

      # rubocop:disable Naming/MemoizedInstanceVariableName
      def contract
        @__contract ||= Spec.new(
          verb: @__verb,
          summary: @__summary,
          args: (@__args || []).freeze,
          surfaces: (@__surfaces || []).freeze,
          views: ((@__views ||= {})[:default] ||= ->(v, _i) { v }) && @__views,
          cli: @__cli,
          cli_stdin: @__cli_stdin,
        )
      end
      # rubocop:enable Naming/MemoizedInstanceVariableName
    end
  end
end
