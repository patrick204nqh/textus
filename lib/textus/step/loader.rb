# frozen_string_literal: true

module Textus
  module Step
    # Convention discovery: glob .textus/steps/<kind>/<name>.rb, load each file,
    # validate the class it defines against the discovered kind, assign the
    # discovered name, and register it. No global queue, no Textus.hook.
    class Loader
      BASE_FOR = {
        fetch: Step::Fetch, transform: Step::Transform,
        validate: Step::Validate, observe: Step::Observe
      }.freeze

      def initialize(registry:)
        @registry = registry
      end

      def load_dir(dir)
        return unless File.directory?(dir)

        loaded_paths = Set.new
        Dir.glob(File.join(dir, "**/*.rb")).sort.each do |path| # rubocop:disable Lint/RedundantDirGlobSort
          real_path = File.realpath(path)
          next if loaded_paths.include?(real_path)

          loaded_paths << real_path
          load_one(dir, path)
        end
      end

      private

      def load_one(dir, path)
        disc = Discovery.parse(path, base: dir)
        klass = capture_defined_class(path, disc)
        validate!(disc, klass, path, dir)

        step = klass.new
        step.name = disc.name
        @registry.register(step)
      rescue StandardError, ScriptError => e
        raise UsageError.new("failed loading step #{rel(dir, path)}: #{e.class}: #{e.message}") unless e.is_a?(UsageError)

        raise
      end

      # Load the file and return the Step::Base subclass it newly defined.
      def capture_defined_class(path, disc)
        before = descendants
        load(path)
        defined = descendants - before
        return defined.first if defined.length == 1
        raise UsageError.new("step #{path} defined more than one Textus::Step subclass") if defined.length > 1

        fallback = find_existing_class_for(disc)
        return fallback if fallback

        raise UsageError.new("step #{path} defined no Textus::Step subclass")
      end

      def find_existing_class_for(disc)
        expected = inferred_class_name_for(disc)
        candidates = descendants.select do |klass|
          klass < BASE_FOR.fetch(disc.kind) && klass.name&.split("::")&.last == expected
        end
        return nil if candidates.empty?
        return candidates.first if candidates.length == 1

        namespaced = candidates.find { |klass| klass.name == "Textus::Step::#{expected}" }
        namespaced || candidates.first
      end

      def inferred_class_name_for(disc)
        stem = disc.name.to_s.split(/[-_]/).map(&:capitalize).join
        suffix = { fetch: "Fetch", transform: "Transform", validate: "Validate", observe: "Observe" }.fetch(disc.kind)
        "#{stem}#{suffix}"
      end

      def validate!(disc, klass, path, dir)
        expected = BASE_FOR.fetch(disc.kind)
        actual_kind = klass.respond_to?(:kind) ? safe_kind(klass) : nil
        unless klass < expected
          raise UsageError.new("#{rel(dir, path)} defines a #{actual_kind || "non-step"} step but lives under #{disc.kind}/")
        end

        sig = Step::Signature.new(klass.instance_method(:call))
        missing = sig.missing(klass.required_kwargs)
        return if missing.empty?

        msg = "#{disc.kind} step '#{disc.name}' #call must accept kwargs: " \
              "#{klass.required_kwargs.join(", ")} (missing: #{missing.join(", ")})"
        raise UsageError.new(msg)
      end

      def safe_kind(klass)
        klass.kind
      rescue StandardError
        nil
      end

      def descendants
        ObjectSpace.each_object(Class).select { |c| c < Step::Base }
      end

      def rel(dir, path) = path.delete_prefix(dir.to_s).delete_prefix("/")
    end
  end
end
