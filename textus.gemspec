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
  s.required_ruby_version = ">= 3.3"

  s.files = Dir[
    "lib/**/*.rb",
    "exe/*",
    "README.md",
    "SPEC.md",
    "CHANGELOG.md",
    "ARCHITECTURE.md",
    "docs/conventions.md",
  ]
  s.bindir = "exe"
  s.executables = ["textus"]

  s.add_dependency "csv", ">= 3.0"
  s.add_dependency "psych", ">= 5.0"
  s.add_dependency "rexml", ">= 3.2"
  s.add_dependency "zeitwerk", "~> 2.6"

  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rspec", "~> 3.13"

  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => "https://github.com/patrick204nqh/textus",
    "bug_tracker_uri" => "https://github.com/patrick204nqh/textus/issues",
    "changelog_uri" => "https://github.com/patrick204nqh/textus/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/patrick204nqh/textus/blob/main/SPEC.md",
    "rubygems_mfa_required" => "true",
  }
end
