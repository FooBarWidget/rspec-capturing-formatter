# Sanitizing captured input

Captured writes are arbitrary byte chunks, not complete lines or even complete characters. `Sanitizer` incrementally converts one captured source into safe UTF-8 while preserving enough state to resolve split encodings, CRLF, and terminal sequences. Destination encoding happens later and belongs to [Report destinations and backpressure](report-destinations-and-backpressure.md).

## Conversion pipeline

For each write, the sanitizer:

1. Uses an explicit source encoding when supplied, otherwise uses the value's encoding. An unknown encoding name falls back to UTF-8.
2. Decodes complete source bytes to internal UTF-8 and retains only an incomplete suffix.
3. Parses line boundaries and terminal controls, retaining a possibly incomplete escape sequence.
4. Returns safe text immediately instead of buffering an ordinary partial line.

UTF-8 uses a bounded suffix carry. BOM-sensitive UTF-16 waits for enough bytes to determine byte order and retains incomplete code units. Other encodings use an incremental `Encoding::Converter`, which preserves stateful encodings such as ISO-2022-JP. Ruby's UTF8 variant encodings use their converter when valid and otherwise fall back to the UTF-8 byte decoder.

If a write changes source encoding, the sanitizer makes incomplete state from the previous encoding visible before selecting a new decoder. `finish` flushes incomplete encoding bytes and escape sequences instead of dropping them or raising.

## Lines and terminal controls

The parser normalizes CRLF to one newline and treats a lone carriage return as a stable line boundary. Tabs, newlines, ordinary text, and valid ANSI Select Graphic Rendition sequences remain intact.

Other terminal-affecting input is converted to visible text. This includes backspace, cursor movement, erase commands, OSC sequences, unsupported escapes, and unsafe C0 or C1 controls. The report therefore shows what the application attempted without executing cursor movement or terminal rewriting.

An incomplete escape sequence is retained through `MAX_ESCAPE_BYTES`. Beyond that bound, or when the sanitizer finishes, the bytes become visible escape text. This prevents hostile or malformed output from causing unbounded buffering.

SGR is the sole preserved terminal-sequence class. Preservation here does not guarantee that it reaches the destination: the renderer retains or removes SGR according to [terminal capability](color-and-terminal-capability.md).

## Invalid and binary data

Invalid UTF-8 and unmappable legacy-encoding bytes become visible `\xNN` escapes. A valid multibyte character split across writes remains intact once its remaining bytes arrive.

`ASCII-8BIT` is treated as binary rather than guessed text. Printable ASCII, tab, carriage return, and newline remain readable; every other byte becomes `\xNN`. Incomplete encoded input receives the same visible treatment when capture finishes.

## Change checklist

Test state boundaries rather than only complete strings when changing sanitization:

- Split UTF-8, UTF-16, and legacy multibyte characters.
- Split, oversized, and incomplete terminal sequences.
- CRLF divided across writes.
- Binary, invalid, and unmappable bytes.
- Source encoding changes with pending state.
- Entry or source changes that force `finish`.
