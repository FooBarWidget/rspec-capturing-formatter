# Architecture and runtime flow

`rspec-capturing-formatter` combines two kinds of output in one append-only report: RSpec notifications about the test run and application writes to `$stdout` and `$stderr`. It captures output by wrapping Ruby's global stream objects instead of replacing operating-system file descriptors, avoiding a background pipe reader and separate platform-specific capture code.

## Component map

- `RSpec::CapturingFormatter` in `lib/rspec/capturing_formatter.rb` interprets [RSpec events and attribution](rspec-events-and-attribution.md), including the active group and example.
- `CaptureManager` and `StreamProxy` in `stream_proxy.rb` own the process-global [capture and stream lifecycle](capture-and-stream-lifecycle.md).
- `Renderer` in `renderer.rb` turns formatter requests and captured text into the [report model](report-model-and-rendering.md), then handles [destination writes and backpressure](report-destinations-and-backpressure.md).
- `Sanitizer` in `sanitizer.rb` incrementally converts each captured source into [safe UTF-8 report text](sanitizing-captured-input.md).
- `WindowsTerminal` decides [terminal color capability](color-and-terminal-capability.md), while `WindowsCommandLine` builds encoded rerun commands that avoid exposing dynamic paths to Windows command parsing.
- `Configuration` validates the process-global formatter settings documented in the public README.

The capture manager is process-global because `$stdout` and `$stderr` are process-global. Each formatter instance has its own renderer and attribution state, but only the formatter holding the manager's active lease receives captured writes.

## Runtime flow

1. Requiring `rspec/capturing_formatter` loads and registers the formatter, then installs inactive proxies into `$stdout` and `$stderr`. Inactive proxies pass writes directly to their backing streams.
2. RSpec constructs the formatter with an output destination. Construction creates the renderer and acquires the manager's single active lease.
3. RSpec notifications update attribution state and ask the renderer to append report content. The manager handles notification callbacks and captured writes under the same reentrant `Monitor`. For each write, it identifies the current example or surrounding context, sanitizes the text, and renders it immediately.
4. The renderer encodes report text for the RSpec destination and writes inside the manager's bypass scope so a destination equal to `$stdout` or `$stderr` cannot capture the report recursively.
5. RSpec sends `stop` after suite hooks. The manager emits any buffered incomplete captured input, releases the lease, restores the original globals, and leaves retained proxies in pass-through raw mode. Later summary, profile, seed, and `close` notifications can still use the renderer, but application writes are no longer attributed.

The manager's monitor protects both formatter callbacks and captured writes. This makes each formatter operation atomic relative to capture; for example, a result cannot split a captured prefix from its payload. It does not establish a chronological order between writes that race on stdout and stderr.

## Configuration interaction

The formatter and renderer retain the process-global configuration object rather than copying its values during construction. Rendering therefore observes settings applied by a spec helper or spec file after RSpec has already constructed the formatter. Keep validation and public option details in `Configuration`, its tests, and the public README rather than duplicating them here.
