#!/usr/bin/env ruby
require "json"
require "textus"

store = Textus::Store.discover(Dir.pwd)

while (line = STDIN.gets)
  req = JSON.parse(line)
  case req["method"]
  when "tools/list"
    puts JSON.generate({
                         "id" => req["id"],
                         "result" => {
                           "tools" => [
                             { "name" => "textus_get",  "description" => "Read a textus entry by key" },
                             { "name" => "textus_list", "description" => "List entries under a prefix" },
                             { "name" => "textus_put",  "description" => "Write to a working entry" },
                           ],
                         },
                       })
  when "tools/call"
    name = req["params"]["name"]
    args = req["params"]["arguments"]
    out =
      case name
      when "textus_get"  then store.get(args["key"])
      when "textus_list" then store.list(prefix: args["prefix"])
      when "textus_put"  then store.put(args["key"], frontmatter: args["frontmatter"], body: args["body"] || "", as: "ai")
      end
    puts JSON.generate({ "id" => req["id"], "result" => out })
  end
  STDOUT.flush
end
