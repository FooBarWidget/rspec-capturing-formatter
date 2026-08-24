# Architecture and runtime flow

`rspec-capturing-formatter` joins two asynchronous inputs into one append-only report: RSpec notifications describe the test run, while Ruby writes through `$stdout` and `$stderr` provide application output. The formatter captures at the Ruby global-stream layer rather than replacing operating-system file descriptors, which avoids a pipe reader and a platform-specific capture backend.

## Component map

- `RSpec::CapturingFormatter` in `lib/rspec/capturing_formatter.rb` interprets [RSpec events and attribution](rspec-events-and-attribution.md), including the active group and example.
- `CaptureManager` and `StreamProxy` in `stream_proxy.rb` own the process-global [capture and stream lifecycle](capture-and-stream-lifecycle.md).
- `Renderer` in `renderer.rb` turns formatter decisions and captured text into the [report model](report-model-and-rendering.md), then handles [destination writes and backpressure](report-destinations-and-backpressure.md).
- `Sanitizer` in `sanitizer.rb` incrementally converts each captured source into [safe UTF-8 report text](sanitizing-captured-input.md).
- `WindowsTerminal` decides [terminal color capability](color-and-terminal-capability.md), while `WindowsCommandLine` quotes rerun arguments for Windows command parsing.
- `Configuration` validates the process-global formatter settings documented in the public README.

The capture manager is process-global because `$stdout` and `$stderr` are process-global. Each formatter instance has its own renderer and attribution state, but only the formatter holding the manager's active lease receives captured writes.

## Runtime flow

1. Requiring `rspec/capturing_formatter` loads and registers the formatter, then installs inactive proxies into `$stdout` and `$stderr`. Inactive proxies pass writes directly to their backing streams.
2. RSpec constructs the formatter with an output destination. Construction creates the renderer and acquires the manager's single active lease.
3. RSpec notifications update attribution state and ask the renderer to append report content. Writes through an active proxy enter the same reentrant monitor, are attributed to the current example or outer context, sanitized, and rendered immediately.
4. The renderer encodes report text for the RSpec destination and writes inside the manager's bypass scope so a destination equal to `$stdout` or `$stderr` cannot capture the report recursively.
5. RSpec sends `stop` after suite hooks. The manager finishes partial captured input, releases the lease, restores the original globals, and leaves retained proxies in pass-through raw mode. Later summary, profile, seed, and `close` notifications can still use the renderer, but application writes are no longer attributed.

The manager's monitor covers both formatter callbacks and captured writes. This makes each formatter operation atomic relative to capture; for example, a result cannot split a captured prefix from its payload. It does not establish a chronological order between writes that race on stdout and stderr.

## Configuration interaction

The formatter and renderer retain the process-global configuration object rather than copying its values during construction. Rendering therefore observes settings applied by a spec helper or spec file after RSpec has already constructed the formatter. Keep validation and public option details in `Configuration`, its tests, and the public README rather than duplicating them here.
