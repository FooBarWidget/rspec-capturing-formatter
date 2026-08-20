# rspec-better-formatter

`rspec-better-formatter` is an RSpec formatter that keeps test progress readable
when examples write logs to stdout or stderr.

It streams logs as they happen, labels their source, and prints the complete
RSpec nesting path before each example. Its output is append-only: it does not
use carriage-return progress, cursor movement, or other terminal rewriting, so
the same report works in a terminal and in CI logs.

## Example

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
  rerun | rspec ./spec/car_spec.rb:20

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

Color and emphasis are omitted from this example. Actual output uses color and
emoji when supported.

## Features

- Streams stdout and stderr in real time with a label on every physical line.
- Shows the full group, context, and example path, separated by `›` by default.
- Reports progress when an example starts and its result when it finishes.
- Attributes `before`, `after`, and `around` example-hook output to the example.
- Gives context and suite-hook output a clear location without inventing an
  example attribution.
- Prints complete failures inline, including RSpec source snippets, aggregate
  failures, filtered backtraces, and `extra_failure_lines` metadata.
- Shows the duration of examples taking at least 500 ms by default.
- Prints reconciled totals for all, succeeded, failed, and pending examples.
- Preserves standard RSpec information such as deprecations, profile output,
  errors outside examples, and the random seed.
- Uses color by default in TTY and non-TTY output, while respecting `NO_COLOR`
  and RSpec's explicit `--no-color` option.
- Uses emoji where the output encoding supports it and readable ASCII symbols
  otherwise.
- Neutralizes cursor movement and erase controls in captured data.
- Uses a Ruby-level capture design that works on Windows without POSIX pipes.

## Requirements

- `rspec-core` >= 3.12

## Usage

Add the formatter to `.rspec`:

```text
--require rspec/better_formatter
--format RSpec::BetterFormatter
```

List `rspec/better_formatter` before other early-required files that construct
loggers. This lets those loggers retain the formatter's stream proxy rather
than an uncapturable reference to the original IO.

Requiring the formatter replaces the two globals with inactive, transparent
proxies even if no run starts. Code that requires `$stdout` or `$stderr` to be
an actual `IO` should not require this gem unless it uses the formatter.

Use this as the sole human-readable console formatter. Machine formatters may
still write to separate files:

```sh
bundle exec rspec \
  --format RSpec::BetterFormatter \
  --format json --out tmp/rspec.json
```

When the better formatter itself is sent to a file with RSpec's `--out`, the
captured stdout and stderr are included in that file as part of the report.

## Configuration

Defaults can be changed with a Ruby configuration block:

```ruby
RSpec::BetterFormatter.configure do |config|
  config.slow_threshold = 0.5 # seconds; nil disables per-example timing
  config.separator = " › "
  config.color = true
  config.emoji = :auto       # :auto, true, or false
end
```

`NO_COLOR` takes precedence when it exists and is non-empty. RSpec's explicit
`--no-color` option also takes precedence. Automatic non-TTY detection does not
disable color because CI-friendly color is a formatter default.

These settings control formatter-generated styling. Captured applications
remain responsible for honoring `NO_COLOR` themselves.

## Output Attribution

The formatter installs process-global proxies for `$stdout` and `$stderr`.
While an example is active, writes through either proxy are attributed to that
example and emitted as `stdout |` or `stderr |`.

RSpec emits group events around `before(:context)` and `after(:context)` hooks.
The formatter uses those events to maintain the current context path. Hook
output outside an active example is emitted as `suite stdout |` or
`suite stderr |`. If no example or earlier hook output has made that context
visible, the full context path is printed first.

Output from `before(:suite)` and `after(:suite)` uses the same suite labels. A
leading `RSpec suite` heading is printed when suite output is the first visible
entry in the report. Formatter-owned example, context, and suite entries are
separated by exactly one empty line.

Top-level output produced while loading spec files after formatter activation
is also suite output. Writes made before formatter activation pass through
unchanged; the proxy is initially inactive so requiring the gem does not hide
or buffer boot output.

Capture ends when RSpec sends its `stop` event, after `after(:suite)` has run.
Writes from lingering threads or `at_exit` handlers after that point pass
through unchanged.

Threads that write while an example is active are attributed to that example.
Writes arriving after the example finishes use the current context or suite
attribution. Writes are synchronized, but an exact chronological ordering
between concurrently written stdout and stderr chunks cannot be guaranteed.
RSpec messages raised during an example are shown inline as `rspec |` lines,
without changing the attribution of later example output.

## Stream Handling

Newline-terminated and partial writes are flushed immediately. If stderr starts
writing while an unterminated stdout line is open, the formatter terminates the
display line and starts a separately labeled stderr line. It never merges data
from different streams onto one report line.

CRLF is normalized to a newline, and a lone carriage return becomes a stable
line boundary. ANSI SGR color sequences in application output are preserved.
Cursor movement, line erasure, backspace, OSC, and other terminal-affecting
controls are rendered harmlessly rather than executed. Formatter styling is
reset at report boundaries so application colors cannot bleed into statuses or
summaries.

Valid text is transcoded for the report destination. Invalid or binary bytes
that cannot be represented safely are shown as escaped byte values instead of
crashing the run or being silently discarded.

## Example Results

Passed, failed, pending, and skipped examples receive distinct status markers.
Pending and skipped examples share the final `pending` count. An example that
was marked pending but unexpectedly passes is an RSpec failure and is reported
as failed. Pending and skipped statuses include their reason and rerun location.
Expected-failure details honor RSpec's `pending_failure_output` setting and are
shown inline rather than duplicated in an end-of-run pending section.

Durations are printed next to results whose run time meets `slow_threshold`.
The suite summary always includes total run time and spec loading time.

Failures are printed immediately below their examples. Formatting is delegated
to RSpec's failure presenter, so existing behavior for source extraction,
compound exceptions, aggregate failures, shared-example traces, backtrace
filtering, and `example.metadata[:extra_failure_lines]` remains intact. A short
rerun list is repeated at the end.

Deprecations continue to use RSpec's configured deprecation stream. Their exact
layout and styling therefore follow the installed RSpec version rather than the
formatter's entry renderer.

Errors raised outside examples are reported by RSpec, counted separately in
the summary, and make the run unsuccessful.

## Capture Boundaries

The formatter captures writes that go through its `$stdout` and `$stderr`
proxies. This includes `puts`, `print`, `warn`, and typical Ruby `Logger`
instances created with one of those globals after the formatter was required.

It does not promise to capture:

- `STDOUT`, `STDERR`, or another reference retained before the proxy was
  installed
- direct native writes to file descriptors 1 or 2
- stdout or stderr inherited by subprocesses
- output intentionally consumed by another capture tool or RSpec's `output`
  matcher

RSpec's `to_stdout_from_any_process` and `to_stderr_from_any_process` matchers
must continue to work; output captured by those matchers is not duplicated in
the formatter report.

RSpec Core runs examples sequentially. Same-process parallel example runners
are unsupported because stdout and stderr are process-global and cannot be
reliably assigned to simultaneous examples. Multi-process runners may be used,
but the runner is responsible for keeping each process's report together.

Using another human-readable formatter on the same output stream can duplicate
progress or make that formatter's direct writes look like test output. Use
separate files for additional formatters.
