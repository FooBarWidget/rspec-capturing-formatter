# Developer handbook

This handbook explains how `rspec-capturing-formatter` works and how to change it safely. Start with the architecture for an end-to-end map, then use the topic descriptions below to find the canonical guidance for a change. The public [README](../README.md) documents installation, configuration, supported behavior, and user-facing limitations.

## Topics

- [Architecture and runtime flow](architecture.md): component boundaries, the require-to-report lifecycle, synchronization, and interactions between capture, RSpec events, rendering, and output destinations.
- [Capture and stream lifecycle](capture-and-stream-lifecycle.md): `$stdout`, `$stderr`, `CaptureManager`, `StreamProxy`, installation, activation leases, raw mode, bypass, threads, nonblocking source writes, and RSpec output matchers.
- [RSpec events and attribution](rspec-events-and-attribution.md): notification phases, example-group state, hook and message attribution, pending and failure semantics, rerun targets, summaries, profiles, seeds, and RSpec API compatibility.
- [Report model and rendering](report-model-and-rendering.md): append-only entries, spacing, source labels, partial physical lines, statuses, timings, failure layout, and final report sections.
- [Sanitizing captured input](sanitizing-captured-input.md): source encodings, split multibyte characters, binary bytes, CRLF, terminal controls, bounded escape parsing, and safe SGR preservation.
- [Report destinations and backpressure](report-destinations-and-backpressure.md): recursive-capture bypass, output ownership, flushes, short writes, `EAGAIN`, pending bytes, destination encodings, BOMs, and ASCII fallbacks.
- [Color and terminal capability](color-and-terminal-capability.md): formatter color preference, `NO_COLOR`, captured SGR, reset boundaries, Windows Terminal detection, Virtual Terminal processing, and the Windows Fiddle requirement.
- [Testing and compatibility](testing-and-compatibility.md): unit versus subprocess tests, global-state isolation, complete-output assertions, `Open3`, supported RSpec versions, Windows coverage, packaging, and documentation updates.
