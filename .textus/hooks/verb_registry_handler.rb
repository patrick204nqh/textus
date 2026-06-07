# Produces verb-reference data (ADR 0097) by introspecting the live CLI verb
# registry. Acquire-only; rendering is the publish template's job (ADR 0094).
#
# Summary resolution: CLI::Verb subclasses do not carry a summary themselves.
# The canonical per-verb summary lives on the Dispatcher use-case contract
# (Textus::Dispatcher::VERBS[verb_name.to_sym].contract.summary). For CLI
# groups (hook, init, key, mcp, rule, schema, zone) that have no Dispatcher
# entry, summary is the empty string — a deliberate accurate representation.
Textus.hook do |reg|
  reg.on(:resolve_handler, :verbs) do |**|
    verbs = Textus::CLI.verbs.sort.map do |name, _klass|
      dispatcher_klass = Textus::Dispatcher::VERBS[name.to_sym]
      summary =
        if dispatcher_klass&.respond_to?(:contract) &&
           (spec = dispatcher_klass.contract) &&
           spec.respond_to?(:summary)
          spec.summary.to_s
        else
          ""
        end

      {
        "name"    => name,
        "summary" => summary,
        "options" => (_klass.respond_to?(:options) ? _klass.options.map { |opt_name, _spec| opt_name.to_s }.sort : []),
      }
    end
    { "content" => { "verbs" => verbs } }
  end
end
