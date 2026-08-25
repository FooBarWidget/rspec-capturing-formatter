require "bundler/gem_tasks"
require "shellwords"

task default: :spec

desc "Run RSpec code examples"
task :spec do
  rspec_args = []

  if ENV["DOGFOOD"]
    rspec_args << "--require"
    rspec_args << "./lib/rspec/capturing_formatter"
    rspec_args << "--format"
    rspec_args << "RSpec::CapturingFormatter"
  end
  if ENV["FORCE_COLOR"]
    rspec_args << "--force-color"
  end
  if (file = ENV["FILE"])
    rspec_args << file
  end
  if (example = ENV["EXAMPLE"])
    rspec_args << "-e"
    rspec_args << example
  end

  ruby [
    "--enable=frozen-string-literal",
    "-S",
    "rspec",
    rspec_args
  ].flatten.compact.map { |x| Shellwords.escape(x) }.join(" ")
end

desc "Run bundle install for all Gemfiles"
task :bundle_install_all do
  Bundler.with_unbundled_env do
    sh "bundle install"
    Dir["gemfiles/*.gemfile"].each do |gemfile|
      sh "env BUNDLE_GEMFILE=#{Shellwords.escape(gemfile)} bundle install"
    end
  end
end

desc "Run bundle update for all Gemfiles"
task :bundle_update_all do
  Bundler.with_unbundled_env do
    sh "bundle update --all"
    Dir["gemfiles/*.gemfile"].each do |gemfile|
      sh "env BUNDLE_GEMFILE=#{Shellwords.escape(gemfile)} bundle update --all"
    end
  end
end
