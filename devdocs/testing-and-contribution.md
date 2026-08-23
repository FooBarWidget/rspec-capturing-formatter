# Testing and contribution

The test suite protects both output details and process-global behavior.

The gem build and installation smoke test runs as part of the integration suite. It checks that the built gem loads and exposes its version.

## Test layers

Unit tests isolate behavior that does not need a real RSpec process:

- configuration validation and defaults;
- sanitizer state, controls, invalid bytes, and encodings;
- renderer spacing, prefixes, styling, timing, and destination encoding;
- proxy IO methods, cloning, reopening, and return values;
- manager leases, activation rollback, bypass, and synchronization;
- Windows argument escaping.

Integration tests run fixture suites in fresh Ruby processes with `Open3`.
They cover:

- global stream installation, restoration, and post-stop passthrough;
- RSpec event order and suite, context, example, and hook attribution;
- loggers, partial writes, stderr, threads, and matcher reopen behavior;
- passed, failed, pending, skipped, fixed-pending, and fail-fast runs;
- failure presenter output, aggregate failures, shared examples, and metadata;
- profile, seed, deprecations, outside-example errors, and JSON separation;
- colors, `NO_COLOR`, non-TTY output, binary data, and encoding boundaries;
- package build and load behavior.

Use argument arrays with `Open3`. Do not build a shell command string. This is required for spaces, quotes, brackets, drive paths, and Windows compatibility.

## Adding a behavior

When changing behavior:

1. Add a focused unit test for local state or formatting.
2. Add a fresh-process integration fixture when globals or RSpec event order are involved.
3. Run the affected tests and any relevant RSpec compatibility suite.

Prefer representative complete-output assertions for spacing and scanability. Normalize only values that are inherently variable, such as durations and temporary paths. Do not hide labels, blank lines, prefixes, or ordering behind overly broad matchers.

## Safe change points

Change capture routing in `CaptureManager` and `StreamProxy`. Change report layout in `Renderer`. Change byte and control handling in `Sanitizer`. Change RSpec event policy in `BetterFormatter`. Keep formatter-owned writes in the renderer and under the manager's monitor.

Do not add a second capture backend for one platform without a separate design.
Do not use a non-reentrant lock around a write that can call back into a proxy.
Do not register RSpec failure or pending dump events because those details are already inline.
