require_relative "lib/textus/version"

Gem::Specification.new do |s|
  s.name        = "textus"
  s.version     = Textus::VERSION
  s.summary     = "Reference implementation of the textus/1 protocol."
  s.description = "Storage convention and JSON wire protocol for agent-readable project memory."
  s.authors     = ["Patrick"]
  s.email       = ["patrick204nqh@gmail.com"]
  s.license     = "MIT"
  s.homepage    = "https://github.com/patrick204nqh/textus"
  s.required_ruby_version = ">= 3.1"

  s.files = Dir["lib/**/*.rb", "lib/textus/profiles/*.yaml", "exe/*", "README.md", "SPEC.md", "docs/**/*.md"]
  s.bindir = "exe"
  s.executables = ["textus"]

  s.add_dependency "psych", ">= 5.0"
  s.add_dependency "csv", ">= 3.0"
  s.add_dependency "rexml", ">= 3.2"

  s.add_development_dependency "rspec", "~> 3.13"
  s.add_development_dependency "rake", "~> 13.0"
end
