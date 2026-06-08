module Textus
  module Jobs
    # Wires the closed allow-list of convergence job types to the existing
    # convergence code. Authority is read from the job's frozen `enqueued_by`
    # and turned into the Call the handler runs under: produce self-elevates
    # inside Produce::Engine regardless; destructive sweep runs AS the caller.
    module Handlers
      module_function

      def registry
        reg = Textus::Domain::Jobs::Registry.new
        reg.register("materialize", handler: method(:produce))
        reg.register("re-pull",     handler: method(:produce))
        reg.register("sweep",       handler: method(:sweep))
        reg
      end

      # produce: render derived / re-pull intake for a single key. Engine
      # self-elevates to the build actor internally; the passed call carries
      # only correlation/dry_run plus the stamped role for audit.
      def produce(job:, container:)
        Textus::Produce::Engine.converge(container: container, call: call_for(job), keys: [job.args["key"]])
      end

      # sweep: compute retention rows for the scope, then apply destructively AS
      # the job's role (no self-elevation).
      def sweep(job:, container:)
        call = call_for(job)
        scope = job.args["scope"]
        rows = Textus::Domain::Retention::Sweep.new(
          manifest: container.manifest,
          file_stat: Textus::Ports::Storage::FileStat.new,
          clock: Textus::Ports::Clock.new,
        ).call(prefix: scope_prefix(scope), zone: scope_zone(scope))
        Textus::Maintenance::Retention::Apply.new(container: container, call: call).call(rows)
      end

      def call_for(job)
        Textus::Call.build(role: job.enqueued_by || Textus::Role::AUTOMATION)
      end

      # A scope is `{ "prefix" => ..., "zone" => ... }` or nil (whole store).
      def scope_prefix(scope) = scope.is_a?(Hash) ? scope["prefix"] : nil
      def scope_zone(scope)   = scope.is_a?(Hash) ? scope["zone"]   : nil
    end
  end
end
