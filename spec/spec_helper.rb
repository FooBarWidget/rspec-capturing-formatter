$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rspec"
require "rspec/capturing_formatter"

RSpec.configure do |config|
  config.disable_monkey_patching! if config.respond_to?(:disable_monkey_patching!)
end
