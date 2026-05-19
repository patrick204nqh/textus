#!/usr/bin/env ruby
require "json"
require "textus"

store = Textus::Store.discover(Dir.pwd)

TOOLS = [
  { "name" => "textus_get",        "description" => "Read a textus entry by key" },
  { "name" => "textus_list",       "description" => "List entries under a prefix" },
  { "name" => "textus_put",        "description" => "Write to a working entry" },
  { "name" => "textus_refresh",    "description" => "Refresh an intake entry via its registered fetcher" },
  { "name" => "textus_extensions", "description" => "List registered fetchers/reducers/hooks" },
].freeze

def list_extensions(store)
  rows = []
  rows += store.registry.fetcher_names.map { |n| { "kind" => "fetcher", "name" => n.to_s } }
  rows += store.registry.reducer_names.map { |n| { "kind" => "reducer", "name" => n.to_s } }
  store.registry.hook_events.each do |evt|
    store.registry.hooks(evt).each do |h|
      rows << { "kind" => "hook", "event" => evt.to_s, "name" => h[:name].to_s }
    end
  end
  rows
end

while (line = STDIN.gets)
  req = JSON.parse(line)
  case req["method"]
  when "tools/list"
    puts JSON.generate({ "id" => req["id"], "result" => { "tools" => TOOLS } })
  when "tools/call"
    name = req["params"]["name"]
    args = req["params"]["arguments"]
    out =
      case name
      when "textus_get"        then store.get(args["key"])
      when "textus_list"       then store.list(prefix: args["prefix"])
      when "textus_put"        then store.put(args["key"], frontmatter: args["frontmatter"], body: args["body"] || "", as: "ai")
      when "textus_refresh"    then Textus::Refresh.call(store, args["key"], as: "script")
      when "textus_extensions" then list_extensions(store)
      end
    puts JSON.generate({ "id" => req["id"], "result" => out })
  end
  STDOUT.flush
end
