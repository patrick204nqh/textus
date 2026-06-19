require_relative "lib/textus/version"

Gem::Specification.new do |s|
  s.name        = "textus"
  s.version     = Textus::VERSION
  s.summary     = "Reference implementation of the textus/3 protocol."
  s.description = "A coordination space for humans, AI, and automation. " \
                  "Durable, multi-writer project memory where each actor writes into its own lane, " \
                  "proposals cross a review queue, and every change is audited."
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
    "docs/architecture/README.md",
    "docs/reference/conventions.md",
  ]
  s.bindir = "exe"
  s.executables = ["textus"]

  s.add_dependency "csv", ">= 3.0"
  s.add_dependency "dry-schema", "~> 1.13"
  s.add_dependency "dry-struct", "~> 1.6"
  s.add_dependency "mcp", "~> 0.20"
  s.add_dependency "psych", ">= 5.0"
  s.add_dependency "rexml", ">= 3.2"
  s.add_dependency "sqlite3", "~> 2.0"
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
