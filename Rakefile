require "bundler/gem_tasks"
require "shellwords"

task default: :spec

desc "Run RSpec code examples"
task :spec do
  rspec_args = []

  if ENV["DOGFOOD"]
    rspec_args << "--require"
    rspec_args << "./lib/rspec/better_formatter"
    rspec_args << "--format"
    rspec_args << "RSpec::BetterFormatter"
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
