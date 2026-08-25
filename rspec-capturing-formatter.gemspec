require_relative "lib/rspec/capturing_formatter/version"

# After updating this
Gem::Specification.new do |spec|
  spec.name = "rspec-capturing-formatter"
  spec.version = RSpec::CapturingFormatter::VERSION
  spec.authors = ["Hongli Lai"]
  spec.summary = "A CI-friendly RSpec formatter that shows logs"
  spec.description = "A CI-friendly RSpec formatter that keeps test progress readable when examples write logs."
  spec.homepage = "https://github.com/rspec-capturing-formatter/rspec-capturing-formatter"
  spec.license = "MIT"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt", "Rakefile"]
  spec.require_paths = ["lib"]

  # After updating dependencies, run `bundle exec rake bundle:install -m`
  # to sync all Bundler lockfiles.

  spec.add_runtime_dependency "rspec-core", ">= 3.12"

  # Below section is for dev dependencies that are *simultaneously* used by all of these:
  # - main Rake+RSpec invocation
  # - version-specific Rake+RSpec invocations (those utilizing gemfiles/*)
  #
  # For dev dependencies used only in 1 of those places, put in the corresponding Gemfile.
  spec.add_development_dependency "rspec", ">= 3.12"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "shellwords"
  spec.add_development_dependency "fiddle"
  spec.add_development_dependency "logger"
end
