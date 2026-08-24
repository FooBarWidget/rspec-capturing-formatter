# Report destinations and backpressure

The renderer must preserve report order while writing to any RSpec formatter destination. That destination may be a global proxy, may use a non-UTF-8 encoding, and may accept only part of a write. This document explains how the renderer prevents recursive capture, buffers and retries partial writes, converts encodings, flushes output, and respects RSpec's ownership of the destination.

## Output path and ownership

Every renderer fragment passes through one output path before reaching the destination. The renderer encodes each fragment, adds it to a buffer, repeatedly writes until the buffer is empty, and then flushes the destination. All report-layout code uses this path.

RSpec owns the formatter destination. The renderer writes and flushes it but does not close it. If RSpec supplies no output, the renderer uses an internal `StringIO`.

The destination can be `$stdout`, `$stderr`, or a proxy retained from installation. Every destination write runs inside the matching `CaptureManager#bypass` scope so formatter output passes through rather than recursively becoming captured application output. The capture side of this interaction is documented in [Capture and stream lifecycle](capture-and-stream-lifecycle.md).

## Short writes and waiting

When the destination supports `write_nonblock`, the renderer uses it; otherwise it uses `write`. A numeric return smaller than the pending byte count advances only by that amount and immediately attempts the remainder. A `nil` return is treated as accepting the complete pending chunk, matching common writer objects that do not return a byte count.

If the destination raises `IO::WaitWritable` or `Errno::EAGAIN`, or returns `:wait_writable`, the renderer saves the unwritten encoded bytes and reports the same wait condition to its caller. It removes bytes the destination already accepted so they are not written again.

`write_nonblock` and `syswrite` need extra retry handling when the destination cannot accept all generated report output. `CaptureManager` saves the original application payload when rendering waits. If the caller retries with the same payload, the manager first writes the remaining report bytes, then returns the original payload's byte count without capturing it again. While that payload is pending, a different payload on the same proxy receives `EAGAIN`.

This saved-payload retry behavior applies only to captured `write_nonblock` and `syswrite`. An ordinary captured `write` reports a destination wait without recording the source payload for retry. Preserve this distinction when changing either layer.

## Return values

Captured write methods return the number of bytes consumed from the application's original input, not the size of the expanded sanitized and prefixed report. This remains true when encoding escapes or labels expand the output. Proxy convenience methods preserve their own Ruby return contracts on top of that byte-count behavior.

## Destination encoding

Sanitization produces UTF-8 report text. Before writing, the renderer converts it to the destination's external encoding when the writer reports one. Characters that cannot be represented become visible `\xNN` or `\u{...}` text and conversion is retried.

Generic UTF-16 and UTF-32 destinations are normalized to a concrete big-endian encoding and receive exactly one byte-order mark. The renderer asks the destination to use that concrete encoding when it supports `set_encoding`.

A writer without encoding metadata receives the renderer's UTF-8 string. If it rejects a non-ASCII pending chunk with an encoding or argument error, the renderer converts non-ASCII bytes to visible `\xNN` escapes and retries. ASCII-only write errors propagate because encoding fallback cannot improve them.
