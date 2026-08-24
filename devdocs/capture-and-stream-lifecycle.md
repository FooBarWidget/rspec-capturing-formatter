# Capture and stream lifecycle

`CaptureManager` and `StreamProxy` make Ruby-level stdout and stderr writes available to the formatter without changing file descriptors. This document explains how proxies are installed and activated, how writes are synchronized, what happens to retained stream references, and how proxies support code that treats the globals as writable IO-like objects.

## Proxy lifecycle

Requiring the formatter installs one long-lived proxy for each global stream. Installation records the original objects and replaces `$stdout` and `$stderr`; it does not replace the `STDOUT` and `STDERR` constants or their file descriptors. Before a formatter is active, the proxies pass bytes to their backing streams, so requiring the gem changes global object identity without hiding boot output.

RSpec constructs a formatter after processing `--require`. The manager installs the proxies if necessary and grants the formatter an owning lease. Any second activation while that lease is active raises, including an activation for the same destination. The lease includes a generation so a stale lease cannot deactivate a later run.

At `stop`, or at `close` as an idempotent fallback, deactivation asks the formatter to emit buffered incomplete input and close any open captured line. It then restores the original globals if they still point to the manager's proxies. Existing logger and thread references can still point to a proxy after restoration, so deactivation puts those retained proxies into raw mode. Their later writes pass directly to the backing stream. The same manager and proxies can be activated again for a later run.

If formatter construction fails, it removes the proxies only if the manager's activation state and generation are unchanged since construction began. Otherwise, cleanup could undo a newer formatter activation.

## Synchronization and bypass

The manager uses a reentrant `Monitor` for activation state, formatter notification handling, and captured writes. Reentrancy is required because a formatter callback can render to an output that is itself one of the managed proxies.

Renderer-owned writes enter `CaptureManager#bypass`. Bypass depth is thread-local and restored in an `ensure` block, so nested renderer writes pass through while unrelated threads remain capturable. The destination-writing side of this interaction is documented in [Report destinations and backpressure](report-destinations-and-backpressure.md).

The monitor serializes competing writes but cannot recover a meaningful order between stdout and stderr writes that race in different threads. A write that arrives after an example's result is attributed to whichever example, context, or suite state is current when the manager handles it.

## Writable IO compatibility

`StreamProxy` implements common writable methods directly because Ruby callers rely on each method's conversion rules and return value, not just on the bytes it writes. It preserves behavior such as `write` returning the consumed source byte count, `puts` returning `nil`, and `<<` returning the proxy. Methods that need no capture-specific handling delegate directly to the backing object.

The proxy is intentionally IO-like rather than an `IO` subclass. Code that requires an actual `IO`, relies on global object identity, writes through `STDOUT` or `STDERR`, or held a stream reference before proxy installation remains outside this capture design. The public README describes the supported capture boundary.

## Reopen and output matchers

RSpec's ordinary output matcher temporarily replaces a global with a `StringIO`; bytes written while it owns the global do not reach the formatter proxy. The `*_from_any_process` matchers instead clone and reopen the current stream. `StreamProxy` supports this sequence by saving the clone's backing stream, putting reopened proxies in raw mode, and restoring the saved stream when RSpec performs the matching reopen. Nested reopen pairs are supported.

Raw mode prevents matcher bytes from receiving report prefixes or appearing both in the matcher result and in the formatter report. This support is specific to RSpec's matcher lifecycle and normal logger use; it does not support code that permanently reopens or otherwise changes the global streams.

## Nonblocking source writes

Inactive or raw proxies forward `write_nonblock` and `syswrite` to the corresponding backing method. During capture, these methods report destination backpressure to their caller in the usual way, even though one application write can produce several report writes. If the report destination cannot accept all output, the manager retains the original source payload so a retry can finish pending report bytes without capturing the payload twice. The complete retry contract belongs to [Report destinations and backpressure](report-destinations-and-backpressure.md).
