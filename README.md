# rspec-capturing-formatter

`rspec-capturing-formatter` is an RSpec formatter that keeps test progress readable when examples write logs to stdout or stderr. This is especially helpful in CI, where interleaved output can make it difficult to tell which example produced a particular log message. By keeping output clearly associated with the example that produced it, the formatter makes failures easier to understand and debug.

Example:

```text
A car › it is red
  ✅ succeeded

A car › it beeps when there is danger
  stdout | starting engine
  stderr | warning: beeper initialization delayed
  ✅ succeeded  812 ms

A car › during maintenance mode
  suite stdout | preparing maintenance fixtures

A car › during maintenance mode › it disables safety guardrails
  stdout | frobnicating the door
  ❌ failed  2.00 s
  rerun  | rspec ./spec/car_spec.rb:20

  Failure/Error: raise "test"

  RuntimeError:
    test

  diagnostic state: maintenance

  # ./spec/car_spec.rb:20

1 deprecation warning total

Summary
  3 total  2 succeeded  1 failed  0 pending
  Finished in 2.90 s  |  files loaded in 98.9 ms

Failed examples
  rspec ./spec/car_spec.rb:20
```

Color and emphasis are omitted from this example. Actual output uses color and emoji when supported.

> [!NOTE]
> On Windows, rerun lines look super weird, like this:
>
> ```
>   rerun  | ruby -e ^"ARGV^[0^]=ARGV.fetch^(0^).unpack1^(\^"m0\^"^).force_encoding^(\^"UTF-8\^"^)^;load^(Gem.bin_path^(\^"rspec-core\^"^,\^"rspec\^"^)^)^" Li9zcGVjL3VuaXQvd2luZG93c19jb21tYW5kX2xpbmVfc3BlYy5yYjo3Ng==
> ```
>
> This is because Windows cmd.exe escaping rules are super complicated. On Windows, RubyGems-installed commands such as `rspec` are actually `.bat` files, thus involving multiple layers of cmd.exe quoting. It's not as straightforward as on Unix where you just escape the value multiple times.
>
> So I gave up. On Windows, rerun commands invoke Ruby directly and contain a Base64-encoded target that doesn't produce any escaping issues. It looks weird, but it works. The LLM gave up trying to solve this problem "properly" after many hours of runs. If you care to improve this, a pull request (with extensive tests) is welcome.

## Usage

Add to your Gemfile:

```ruby
gem "rspec-capturing-formatter"

# For terminal color support on Windows
gem "fiddle", platforms: [:windows]
```

Add the formatter to `.rspec`:

```text
--require rspec/capturing_formatter
--format RSpec::CapturingFormatter
```

List `rspec/capturing_formatter` before other early-required files that construct loggers. This allows output from those loggers to be included in the report.

Before an RSpec run starts, requiring the formatter does not hide or buffer boot output. Code that requires `$stdout` or `$stderr` to be an actual `IO` should not require this gem unless it uses the formatter.

Use this as the sole human-readable console formatter. Machine formatters may still write to separate files:

```sh
bundle exec rspec \
  --require rspec/capturing_formatter \
  --format RSpec::CapturingFormatter \
  --format json --out tmp/rspec.json
```

## Configuration

Defaults can be changed with a Ruby configuration block:

```ruby
RSpec::CapturingFormatter.configure do |config|
  config.slow_threshold = 0.5 # seconds; nil disables per-example timing
  config.separator = " › "
  config.color = true
  config.emoji = :auto       # :auto, true, or false
  config.pending_failure_output = :full # :full, :no_backtrace, or :skip
end
```

When `config.color == true`, coloring is enabled even when there is no TTY. Coloring is always disabled when `NO_COLOR` or when RSpec's `--no-color` option is set.

On Windows, interactive coloring is supported in Windows Terminal. Legacy Windows console sessions are not supported color targets and receive plain-text output instead of raw ANSI escape sequences. Redirected reports keep ANSI coloring when enabled, so they can be viewed by ANSI-aware CI logs or tools.

## Output capture limitations

The formatter captures writes made through `$stdout` and `$stderr` after the formatter is loaded. This includes calls to bare `puts`, `print`, `warn`, and calls to typical Ruby `Logger` instances that log to stdout or stderr.

This formatter does not capture direct native writes to file descriptors 1 or 2, or output written by subprocesses.

Same-process parallel example runners are unsupported because the formatter cannot reliably assign simultaneous stdout and stderr writes to individual examples. Multi-process runners may be used, but the runner is responsible for keeping each process's report together.
