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

  spec.add_dependency "sqlite3", "~> 2.0"
  # sqlite-vec is required at runtime but not declared as a dependency
  # because it only publishes arm64-linux gems, not aarch64-linux,
  # which breaks bundler resolution on aarch64 Docker containers.
  # Users must add `gem "sqlite-vec"` to their own Gemfile.
  spec.add_dependency "informers"
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activejob", ">= 7.0"
end
