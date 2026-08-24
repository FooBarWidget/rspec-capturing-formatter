# Report model and rendering

`Renderer` is the only component that constructs human-readable report output. It turns formatter requests and captured text into append-only report entries, keeps partial output lines readable, applies presentation settings, and writes the result through the shared destination-writing code.

## Entry model

An entry groups content that should be read together. An example heading, captured output, result, rerun command, and failure details form one entry. Context or suite output remains in its current entry until a group transition, example, RSpec message section, profile, summary, rerun list, or seed starts another entry.

Before starting an entry, the renderer completes any open captured source line. It writes exactly one blank line when an earlier entry exists, then records the new entry kind and path. The renderer never rewrites earlier output or depends on terminal width.

RSpec event interpretation decides which entry to request and what the data means. See [RSpec events and attribution](rspec-events-and-attribution.md) for group paths, hook ownership, pending semantics, failure presenters, and final notification order.

## Captured physical lines

Captured text is emitted immediately, including an unterminated partial line. Every physical line starts with two spaces, a source label, and ` | `. The labels are `stdout` and `stderr` inside an example, `suite stdout` and `suite stderr` outside an example, and `rspec` for RSpec-owned messages.

The renderer remembers whether a captured display line is open. More bytes from the same source continue that line without another prefix. A source change finishes the old line before starting one with the new label, so stdout and stderr payload never share a display line. A newline-terminated chunk does not leave a dangling prefix.

Each source has its own incremental sanitizer. The renderer calls a sanitizer's `finish` method when capture changes source or another report operation creates a boundary; this emits any buffered incomplete bytes and escape sequences. Source-byte and terminal-control behavior is documented in [Sanitizing captured input](sanitizing-captured-input.md).

## Results and timing

Passed, failed, pending, and skipped results have distinct labels and colors. Pending and skipped remain separate display states even though both contribute to RSpec's pending summary count. The renderer uses emoji when the `emoji` setting allows them and the destination encoding can represent them; otherwise it uses fixed ASCII labels.

A result includes duration only when its runtime meets `slow_threshold`. Values below one second are shown as whole milliseconds; values at or above one second use seconds with two decimal places. A `nil` threshold disables per-example durations. Pending and skipped results follow the same presentation rule.

## Failures and final sections

Failure lines preserve RSpec's presenter text while indenting it under the example. Inline rerun lines use `rerun  |`, with two spaces before the separator so it aligns with captured source labels.

The summary is its own entry and displays total, succeeded, failed, pending, suite duration, load time, and any nonzero errors outside examples. Profile output, the failed-example rerun list, and seed output each use a separate entry when requested.

## Styling boundary

The renderer owns formatter colors, status glyphs, source-label styling, and resets around formatter-owned content. Sanitized application SGR can remain in captured payload without becoming formatter styling. The complete preference, capability, and reset policy is documented in [Color and terminal capability](color-and-terminal-capability.md).

The renderer sends every fragment through one output path, which encodes and flushes it. Report-layout methods must not handle short writes or destination failures themselves; see [Report destinations and backpressure](report-destinations-and-backpressure.md).
