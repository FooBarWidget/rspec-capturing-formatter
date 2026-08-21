# Sanitization and encoding

Captured output is not assumed to be complete text in one write. A logger can
split a multibyte character, CRLF, or escape sequence across writes. Each
source has a `Sanitizer` with state that survives until the stream changes or
the renderer finishes the entry.

## Conversion pipeline

The sanitizer follows this pipeline:

1. Resolve the source encoding from the write value or the explicit encoding.
2. Decode the bytes to internal UTF-8 text.
3. Retain an incomplete encoded character for the next write.
4. Parse line boundaries and terminal controls.
5. Return safe report text to the renderer.

UTF-8 uses a small suffix carry. UTF-16 detects a BOM and retains incomplete
code units. Other encodings use an incremental `Encoding::Converter`, which
also preserves stateful encodings such as ISO-2022-JP. `ASCII-8BIT` is treated
as bytes rather than as guessed text.

If a write changes source encoding, incomplete escape and encoding state from
the previous encoding is flushed as visible byte escapes before the new
converter is selected. `finish` flushes all remaining state at an entry or
stream boundary.

## Line and control handling

The parser normalizes CRLF to one newline and makes a lone carriage return a
stable line boundary. It preserves ordinary text, tabs, newlines, and valid
ANSI SGR styling sequences.

Terminal-affecting controls are never executed:

- backspace becomes a visible byte escape;
- cursor movement and erase CSI sequences become visible escape text;
- OSC sequences become visible text and their control terminator is escaped;
- unsupported escape sequences are made visible;
- unsafe C0 and C1 controls become `\xNN` text.

The parser waits for a possibly incomplete sequence, but only up to
`MAX_ESCAPE_BYTES` bytes. An incomplete sequence at the limit is emitted
visibly. This prevents hostile output from causing unbounded buffering.

The sanitizer does not buffer ordinary partial lines. The renderer emits them
at once and only retains the minimum state needed to determine the next
character or control sequence.

## Invalid and binary data

Invalid UTF-8 is not discarded. Invalid bytes become visible `\xNN` escapes,
while a valid character that starts in one write and ends in the next remains
intact.

For `ASCII-8BIT`, printable ASCII plus tab, CR, and LF remain readable. All
other bytes become `\xNN` escapes. Invalid or unmappable data from legacy
encodings follows the same visible-escape rule. Incomplete encoded data is
escaped at shutdown instead of raising or disappearing.

## Report destination encoding

After sanitization, `Renderer` encodes report text for the destination's
external encoding. It handles UTF-16 and UTF-32 BOM-sensitive destinations and
writes at most one BOM. If a character cannot be represented, it becomes a
visible `\xNN` or `\u{...}` escape before the write is retried.

Writers without encoding metadata are supported. If such a writer rejects a
non-ASCII chunk, the renderer falls back to visible byte escapes. The proxy's
write return value still reports the original input byte count, not the size of
the rendered report.

## Styling safety

SGR is the one class of terminal sequence intentionally preserved because it
represents application styling. The renderer detects both ordinary and modern
colon-form SGR sequences. It inserts a reset before formatter-owned content and
when capture ends. This keeps application colors inside their captured text.

When changing this code, test boundaries rather than only complete strings:

- split UTF-8, UTF-16, and legacy multibyte characters;
- split and incomplete escape sequences;
- CRLF split across writes;
- binary and invalid bytes;
- source encoding changes;
- destination encodings that cannot represent the path or status glyph.
