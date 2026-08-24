# Architecture and flow

`rspec-better-formatter` is a Ruby-level RSpec formatter. It captures writes through the Ruby `$stdout` and `$stderr` globals, converts them into report entries, and writes an append-only report to the formatter destination.

The design does not replace operating-system file descriptors. This is the main reason it works on Windows without a pipe reader or a descriptor-specific backend.

## Main components

The runtime is split into these components:

- `RSpec::BetterFormatter` in `lib/rspec/better_formatter.rb` receives RSpec notifications and maintains attribution state.
- `CaptureManager` in `stream_proxy.rb` owns the process-global proxies, the active formatter lease, synchronization, and the bypass scope.
- `StreamProxy` in `stream_proxy.rb` presents a writable-IO surface and routes writes either to capture or to its backing stream.
- `Renderer` in `renderer.rb` owns report entries, spacing, prefixes, status lines, failures, summaries, encoding, styling, and flushes. The platform color policy is documented in [Color support](color-support.md).
- `Sanitizer` in `sanitizer.rb` converts captured bytes into safe UTF-8 report text while retaining state across writes.
- `Configuration` in `configuration.rb` validates the five formatter settings.
- `WindowsCommandLine` creates pasteable Windows rerun arguments.
- `WindowsTerminal` detects supported interactive Windows color output and enables Virtual Terminal processing.

The capture manager is process-global. Each formatter instance has its own renderer. The manager routes captured writes only to the formatter that owns the active lease, and can activate only one formatter instance at a time.

## Require and run flow

Requiring `rspec/better_formatter` performs two global actions:

1. It loads the formatter classes and registers the notification methods.
2. It installs inactive proxies into `$stdout` and `$stderr`.

The proxies pass writes to their original streams while inactive. This makes require-only use transparent in output, but it changes the identity and class of the global objects. Code that requires an actual `IO` object must account for this behavior.

RSpec loads files given by `--require` before it constructs the configured formatter. A logger created after the gem is required therefore retains a proxy and can be captured when the run starts. A stream reference retained before installation is outside the capture contract.

Formatter construction follows this order:

1. Save the output destination.
2. Obtain the process-global capture manager, unless an isolated manager was injected for a unit test.
3. Construct the renderer.
4. Initialize event and attribution state.
5. Acquire an activation lease from the manager.

The optional `capture_manager:` initializer argument exists for unit-test isolation. Normal RSpec construction uses the process-global manager, so it still enforces one active formatter for the process. The renderer receives the same manager so formatter-owned writes use the matching bypass scope.

If construction or activation raises, the manager rolls back its installation when it is safe to do so and re-raises the original exception.

During the run, RSpec calls the formatter notification methods. The formatter updates its state under the manager's reentrant monitor. Captured writes use the same monitor, so a result cannot split a captured report line. At the `stop` event, after `after(:suite)`, the manager finishes any partial capture, deactivates the proxies, and restores the original globals. `close` repeats this operation as an idempotent fallback.

The formatter keeps its renderer state after `stop` because RSpec sends summary, profile, seed, or close notifications later. Writes after deactivation pass through without formatter attribution.

## Configuration

`RSpec::BetterFormatter.configuration` is a process-global configuration
object. Use `RSpec::BetterFormatter.configure` to change it:

```ruby
RSpec::BetterFormatter.configure do |config|
  config.slow_threshold = 0.5
  config.separator = " › "
  config.color = true
  config.emoji = :auto
  config.pending_failure_output = :full
end
```

The defaults are `0.5`, `" › "`, `true`, `:auto`, and `:full`. `slow_threshold` accepts a non-negative number or `nil`; `separator` must be non-empty; `color` must be a boolean; `emoji` must be `:auto`, `true`, or `false`; and `pending_failure_output` must be `:full`, `:no_backtrace`, or `:skip`.

The formatter stores the configuration object, not a copy of its values. `Renderer` reads the settings while rendering. This is required because a spec helper or a loaded spec file can configure the formatter after RSpec has constructed it.

## Design constraints

Keep these constraints when changing the architecture:

- Use append-only output. Do not add carriage-return progress or cursor movement.
- Keep one human-readable formatter on a report stream. Put machine-readable formatters on separate files.
- Keep capture at the Ruby global stream layer. Do not add POSIX pipes or fork based capture as a fallback for Windows.
- Keep formatter-owned writes inside `CaptureManager#bypass` so the report does not capture itself.
- Treat stdout and stderr as process-global. Same-process parallel examples cannot be attributed reliably and are unsupported.
- Do not close RSpec's formatter output from the proxy or renderer.
