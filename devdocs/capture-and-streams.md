# Capture and stream lifecycle

The capture manager is the boundary between Ruby IO behavior and formatter behavior. It owns two long-lived `StreamProxy` objects, one for stdout and one for stderr.

## Manager state

`CaptureManager` keeps:

- the original stdout and stderr objects;
- the installed proxies;
- whether capture is active;
- the active formatter and its output destination;
- a monotonically increasing generation number;
- pending nonblocking writes;
- a reentrant `Monitor` for all manager and formatter operations.

The manager uses a lease for every activation. An owning lease records the activation generation. A formatter with the same destination can receive a non-owning lease, but a different concurrent destination is rejected. A stale owning lease cannot deactivate a later generation.

`stop` and `close` are safe to call more than once. After deactivation, the retained proxies enter raw mode. Old logger instances and threads can continue to write through them after the globals have been restored. A later run can activate the same manager again.

## Write path

An active proxy sends `write`, `write_nonblock`, or `syswrite` to
`CaptureManager#handle_write`:

1. The manager enters its monitor.
2. It completes any pending nonblocking report write.
3. It checks for inactive mode, bypass mode, or proxy raw mode.
4. It either writes the original bytes to the backing stream or calls the formatter's `capture` method.
5. It returns the input byte count, or preserves the nonblocking wait/error.

Formatter capture calls the renderer. The renderer sanitizes each stream incrementally, prefixes physical lines, writes the report, and flushes the destination. The manager monitor remains the synchronization boundary around this operation.

The renderer writes in a bypass scope. The output destination can be `$stdout` or `$stderr`, so bypassing is required to avoid recursive capture. Bypass depth is stored per thread and is restored in an `ensure` block.

## Stream proxy behavior

The proxy explicitly implements the common writable-IO methods:

- `write`, `write_nonblock`, `syswrite`, and `<<`;
- `puts`, `print`, `printf`, and `putc`;
- `flush`, `sync`, `sync=`, `tty?`, `isatty`, and `closed?`;
- encoding methods, `binmode`, `fileno`, and `to_io`;
- `reopen` and delegation for capabilities provided by the backing object.

It preserves important Ruby return values. `write` returns consumed bytes, `puts` returns `nil`, and `<<` returns the proxy. `puts` handles no arguments, `nil`, nested arrays, recursive arrays, and values that already end in the correctly encoded newline. `print` honors Ruby's output field and record separators. `putc` writes the low byte for an integer.

When inactive, nonblocking methods call the equivalent method on the backing stream. When active, `write_nonblock` and `syswrite` retain a payload if the report destination raises `EAGAIN` or `IO::WaitWritable`. A retry with the same payload resumes the write without duplicating bytes.

## Reopen and RSpec matchers

RSpec's ordinary output matcher temporarily replaces a global with a `StringIO`. Its writes are outside the formatter until the matcher restores the proxy.

The `*_from_any_process` matchers clone and reopen the current proxy. The proxy supports this sequence by:

- cloning its backing stream and raw-mode state in `initialize_copy`;
- switching to raw mode when reopened onto another IO;
- sending matcher bytes to that raw backing stream without report prefixes;
- restoring the cloned backing state when the matcher reopens the clone;
- supporting nested reopen pairs.

This behavior is important even though child-process descriptor writes are not part of the formatter capture contract. The matcher must see its expected raw bytes, and those bytes must not appear a second time in the report.

Do not treat arbitrary permanent global stream mutation as supported. The proxy is designed for RSpec's matcher lifecycle and normal Ruby logger use.

## Capture boundaries

Captured:

- writes through the active `$stdout` and `$stderr` proxies;
- `puts`, `print`, `warn`, and common `Logger` instances that retain a proxy;
- writes from threads while an example is active.

Not captured:

- direct `STDOUT` or `STDERR` references retained before installation;
- native writes to file descriptors 1 and 2;
- child-process output inherited from the parent;
- bytes intentionally consumed by another capture tool or output matcher;
- writes after RSpec sends `stop`.

Threads are synchronized, but concurrent stdout and stderr chunks do not have a guaranteed cross-stream chronological order. A write arriving after an example finishes is assigned to the current context or suite, not to the completed example.
