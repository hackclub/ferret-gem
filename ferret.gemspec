# frozen_string_literal: true

require_relative "lib/ferret/version"

Gem::Specification.new do |spec|
  spec.name = "ferret"
  spec.version = Ferret::VERSION
  spec.authors = ["Hack Club"]
  spec.summary = "Vector search + rerank for ActiveRecord, backed by a sidecar SQLite database"
  spec.homepage = "https://github.com/hackclub/ferret"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activejob", ">= 7.0"
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "informers"
  spec.add_dependency "sqlite3", "~> 2.0"
  spec.add_dependency "sqlite-vec", "~> 0.1.7.alpha.10"
end
