# Testing and contribution

The test suite protects both output details and process-global behavior. Use the public README as the behavior contract, then update the handbook when a design decision or boundary changes.

## Commands

Run the default suite with:

```sh
bundle exec rspec
```

Check the supported dependency sets that have checked-in Gemfiles explicitly:

```sh
BUNDLE_GEMFILE=gemfiles/rspec_3_12.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/rspec_3_13.gemfile bundle exec rspec
```

The CI workflow creates a temporary Gemfile to also check RSpec 4.0. It runs each supported RSpec version on Linux and Windows. The native `cmd.exe` quoting example is intentionally skipped on non-Windows systems. A Linux pass does not verify that native shell behavior.

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

1. Identify the public promise in `README.md`.
2. Add a focused unit test for local state or formatting.
3. Add a fresh-process integration fixture when globals or RSpec event order are involved.
4. Run the default suite and the relevant RSpec compatibility Gemfile.
5. Update the README if the public behavior changed.
6. Update the relevant handbook topic if the design or boundary changed.

Prefer representative complete-output assertions for spacing and scanability. Normalize only values that are inherently variable, such as durations and temporary paths. Do not hide labels, blank lines, prefixes, or ordering behind overly broad matchers.

## Safe change points

Change capture routing in `CaptureManager` and `StreamProxy`. Change report layout in `Renderer`. Change byte and control handling in `Sanitizer`. Change RSpec event policy in `BetterFormatter`. Keep formatter-owned writes in the renderer and under the manager's monitor.

Do not add a second capture backend for one platform without a separate design.
Do not use a non-reentrant lock around a write that can call back into a proxy.
Do not register RSpec failure or pending dump events because those details are already inline.

## Writing style

Use sentence case for headings and subheadings. Use ASD-STE100 Simplified Technical English. Keep comments short and explain only non-obvious design choices. Document current behavior and explicit limitations instead of describing an ideal implementation that the tests do not enforce.
