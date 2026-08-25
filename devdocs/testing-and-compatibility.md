# Testing and compatibility

Tests should cover observable behavior without making every assertion mirror the formatter's internal classes and methods. This document explains where a test belongs, which global state it must isolate, and when compatibility or documentation work is required.

## Choose the test boundary

Use a unit test when behavior can be exercised without a real RSpec process. Configuration, sanitization, report layout, destination writing, proxy semantics, manager leases, Windows command quoting, and injected terminal capability all have independent units.

Use an integration test in a fresh process when the behavior depends on requiring the gem, replacing global streams, RSpec notification order, hooks, formatter combinations, deprecations, or process shutdown. Integration tests invoke fixture suites through `Open3`, which prevents the suite's proxies and global RSpec state from leaking into the test process.

Pass an argument array to `Open3`; do not build a shell command string. Arrays preserve spaces, quotes, brackets, drive paths, and Windows command behavior without adding an unintended shell parsing layer.

Formatter unit tests that construct `CapturingFormatter` pass a fresh `CaptureManager` through `capture_manager:`. This prevents the formatter running for this project's own test suite from conflicting with the formatter under test while lease and integration tests continue to cover the process-global singleton.

## Isolate global state

Capture tests can mutate `$stdout`, `$stderr`, process-global formatter configuration, RSpec configuration, and environment variables such as `NO_COLOR` and `WT_SESSION`. Restore each value in `ensure` or an equivalent RSpec cleanup even when the example raises. Use a separate process when restoring the global state after a test still cannot reproduce the real interaction reliably.

Do not use a non-reentrant lock around destination writes: the destination can call through a managed proxy and re-enter the manager. Concurrency tests should coordinate with queues or another deterministic boundary rather than relying on sleep ordering.

## Assert report behavior

Prefer representative complete-output assertions when changing spacing, prefixes, or section order. Normalize only inherently variable values such as durations and temporary paths. Broad matchers that hide blank lines, source labels, resets, or ordering can hide changes and allow the output to become harder to scan.

For stateful byte handling, exercise splits at every relevant boundary rather than testing only a complete string. For process-global behavior, assert both activation behavior and restoration or post-stop passthrough.

## RSpec compatibility

The gemspec accepts `rspec-core >= 3.12`, and the maintained bundles exercise RSpec 3.12, 3.13, and the 4.0 prerelease currently locked to beta1 on Linux and Windows. Event code uses capability checks where notification and failure-presenter APIs differ. A change to registration, result interpretation, presenter calls, profile fields, rerun metadata, or final notification order requires the affected focused tests plus every maintained RSpec Gemfile.

Avoid version checks when an API capability check expresses the actual requirement. Keep code that handles RSpec API differences in `CapturingFormatter` so `Renderer` always receives the same kinds of rendering request.

Windows command quoting and Windows Terminal capability fail for different reasons. Keep their tests separate: command tests protect the fixed Ruby bootstrap and encoded rerun target from `cmd.exe`, while terminal-color tests cover environment checks and Fiddle failures. When Wine and `winegcc` are installed, the command test compiles a small argv printer and exercises this boundary on Linux; Windows also runs the complete decode through native Ruby. Native console-handle selection and Virtual Terminal mode changes still require manual testing in an interactive Windows environment.

## Packaging and documentation

Run the gem build and installation smoke path when changing the gemspec, packaged files, load paths, or runtime requirements. It verifies that the built gem loads from its temporary installation rather than relying on the source checkout.

When a change affects installation, configuration, supported output, or limitations, update the public README in the same change. When it changes architecture, major behavior, rationale, or a subsystem boundary, update the canonical handbook topic. Keep README examples representative of the report rather than turning them into an exhaustive specification.
