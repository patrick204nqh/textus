require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "json" => "Json",
  "yaml" => "Yaml",
)
loader.ignore(File.expand_path("textus/errors.rb", __dir__))
loader.setup
loader.eager_load

module Textus
end
