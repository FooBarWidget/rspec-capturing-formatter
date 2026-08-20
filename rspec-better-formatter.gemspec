require_relative "lib/rspec/better_formatter/version"

Gem::Specification.new do |spec|
  spec.name = "rspec-better-formatter"
  spec.version = RSpec::BetterFormatter::VERSION
  spec.authors = ["rspec-better-formatter contributors"]
  spec.summary = "An append-only, log-friendly RSpec formatter"
  spec.description = "An RSpec formatter that keeps test progress readable when examples write logs."
  spec.homepage = "https://github.com/rspec-better-formatter/rspec-better-formatter"
  spec.license = "MIT"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt", "Rakefile"]
  spec.require_paths = ["lib"]
  spec.add_runtime_dependency "rspec-core", ">= 3.12"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", ">= 3.12"
  spec.add_development_dependency "logger"
end
