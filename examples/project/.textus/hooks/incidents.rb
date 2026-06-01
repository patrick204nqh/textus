# Pulls a recent-incidents snapshot into feeds.incidents. The ops team drops a
# JSON export at the repo root; this hook reads it (YOU own the I/O) and delegates
# the PARSE to the built-in :json handler via caps.rpc — textus core makes no
# network calls (SPEC §5.4). The entry is tracked:false, so the fetched file is
# gitignored (incident data is operational/noisy) yet stays readable through the
# protocol. See ../../../docs/cookbook/intake-recipes.md for HTTP/RSS/iCal variants.
Textus.hook do |reg|
  reg.on(:resolve_intake, :incidents) do |caps:, config:, args:|
    path = File.join(File.dirname(caps.root), config.fetch("path"))
    body = File.read(path)                                  # local read, no network
    caps.rpc.invoke(:resolve_intake, :json,                 # delegate to the built-in parser
                    caps: caps, config: { "bytes" => body }, args: args)
  end
end
