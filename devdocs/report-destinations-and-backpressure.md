# Report destinations and backpressure

The renderer must preserve report order while writing to an arbitrary RSpec formatter destination. That destination may be a global proxy, may use a non-UTF-8 encoding, and may accept only part of a write. This topic owns recursion prevention, pending report bytes, retry behavior, destination encoding, flushing, and output ownership.

## Output path and ownership

Every renderer fragment passes through one output path before reaching the destination. The renderer encodes the fragment, appends it to pending output, drains those bytes in order, and flushes the destination after the pending buffer is empty. Layout code does not write around this path.

RSpec owns the formatter destination. The renderer writes and flushes it but does not close it. If RSpec supplies no output, the renderer uses an internal `StringIO`.

The destination can be `$stdout`, `$stderr`, or a proxy retained from installation. Every destination write runs inside the matching `CaptureManager#bypass` scope so formatter output passes through rather than recursively becoming captured application output. The capture side of this interaction is documented in [Capture and stream lifecycle](capture-and-stream-lifecycle.md).

## Short writes and waiting

When the destination supports `write_nonblock`, the renderer uses it; otherwise it uses `write`. A numeric return smaller than the pending byte count advances only by that amount and immediately attempts the remainder. A `nil` return is treated as accepting the complete pending chunk, matching common writer objects that do not return a byte count.

If the destination raises `IO::WaitWritable` or `Errno::EAGAIN`, or returns `:wait_writable`, the renderer keeps the unwritten encoded bytes and propagates the wait. Already accepted bytes are removed from the pending buffer and are not written again.

Captured `write_nonblock` and `syswrite` add a second retry layer. `CaptureManager` remembers the original source payload when rendering waits. A retry with that same payload first drains the renderer's pending report bytes and then returns the original payload byte count without capturing it again. A different nonblocking payload on the same proxy cannot overtake the pending one and receives `EAGAIN`.

This source-payload replay contract applies only to captured `write_nonblock` and `syswrite`. An ordinary captured `write` propagates a destination wait without recording source payload state. Preserve this distinction when changing either layer.

## Return values

Captured write methods report consumption in terms of the application's original source bytes, not the larger sanitized and prefixed report. This remains true when encoding escapes or labels expand the output. Proxy convenience methods preserve their own Ruby return contracts on top of that byte-count behavior.

## Destination encoding

Sanitization produces UTF-8 report text. Before writing, the renderer converts it to the destination's external encoding when the writer reports one. Characters that cannot be represented become visible `\xNN` or `\u{...}` text and conversion is retried.

Generic UTF-16 and UTF-32 destinations are normalized to a concrete big-endian encoding and receive exactly one byte-order mark. The renderer asks the destination to use that concrete encoding when it supports `set_encoding`.

A writer without encoding metadata receives the renderer's UTF-8 string. If it rejects a non-ASCII pending chunk with an encoding or argument error, the renderer converts non-ASCII bytes to visible `\xNN` escapes and retries. ASCII-only write errors propagate because encoding fallback cannot improve them.
