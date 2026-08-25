require "bundler/gem_tasks"

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

  ruby(*[
    "--enable=frozen-string-literal",
    "-S",
    "rspec",
    rspec_args
  ].flatten.compact)
end

def tested_rspec_versions
  @tested_rspec_versions ||= Dir["gemfiles/*.gemfile"].map do |path|
    File.basename(path).sub(/\..*/, "")
  end
end

desc "Run bundle install for all Gemfiles"
task "bundle:install" => [
  "bundle:install:main",
  tested_rspec_versions.map { |rspec_version| "bundle:install:#{rspec_version}" }
].flatten

desc "Run bundle update for all Gemfiles"
task "bundle:update" => [
  "bundle:update:main",
  tested_rspec_versions.map { |rspec_version| "bundle:update:#{rspec_version}" }
].flatten

desc "Run bundle install for main Gemfile"
task "bundle:install:main" do
  Bundler.with_unbundled_env do
    sh "bundle install"
  end
end

desc "Run bundle update for main Gemfile"
task "bundle:update:main" do
  Bundler.with_unbundled_env do
    sh "bundle update --all"
  end
end

tested_rspec_versions.each do |rspec_version|
  desc "Run bundle install for #{rspec_version} Gemfile"
  task "bundle:install:#{rspec_version}" do
    Bundler.with_unbundled_env do
      sh "env BUNDLE_GEMFILE=gemfiles/#{Shellwords.escape(rspec_version)}.gemfile bundle install"
    end
  end

  desc "Run bundle update for #{rspec_version} Gemfile"
  task "bundle:update:#{rspec_version}" do
    Bundler.with_unbundled_env do
      sh "env BUNDLE_GEMFILE=gemfiles/#{Shellwords.escape(rspec_version)}.gemfile bundle update --all"
    end
  end
end
