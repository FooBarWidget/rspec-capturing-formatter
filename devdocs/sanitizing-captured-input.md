# Sanitizing captured input

Captured writes can be arbitrary byte chunks, not complete lines or even complete characters. `Sanitizer` converts each captured source to safe UTF-8 over multiple writes, keeping enough state to handle split encodings, CRLF, and terminal sequences. Destination encoding happens later and belongs to [Report destinations and backpressure](report-destinations-and-backpressure.md).

## Conversion pipeline

For each write, the sanitizer:

1. Uses an explicit source encoding when supplied, otherwise uses the value's encoding. An unknown encoding name falls back to UTF-8.
2. Decodes complete source bytes to internal UTF-8 and retains only an incomplete suffix.
3. Parses line boundaries and terminal controls, retaining a possibly incomplete escape sequence.
4. Returns safe text immediately instead of buffering an ordinary partial line.

For UTF-8, the sanitizer keeps a small, bounded number of trailing bytes when a character is split across writes. UTF-16 with a byte-order mark waits until it can determine the byte order and keeps any incomplete code unit for the next write. Other encodings use `Encoding::Converter`, which retains decoding state for encodings such as ISO-2022-JP. Ruby's UTF8 variant encodings use their converter when valid and otherwise fall back to the UTF-8 byte decoder.

If a write changes source encoding, the sanitizer emits incomplete bytes and escape sequences from the previous decoder before selecting a new one. `finish` emits incomplete encoding bytes and escape sequences instead of dropping them or raising.

## Lines and terminal controls

The parser normalizes CRLF to one newline and treats a lone carriage return as the end of a line rather than as terminal cursor movement. Tabs, newlines, ordinary text, and valid ANSI Select Graphic Rendition sequences remain intact.

The sanitizer prints other terminal-affecting input as visible text instead of sending it to the terminal. This includes backspace, cursor movement, erase commands, OSC sequences, unsupported escapes, and unsafe C0 or C1 controls. The report therefore shows what the application attempted without executing cursor movement or terminal rewriting.

The sanitizer buffers an incomplete escape sequence up to `MAX_ESCAPE_BYTES`. Longer or unfinished sequences become visible escape text. This prevents hostile or malformed output from causing unbounded buffering.

SGR is the sole preserved terminal-sequence class. Preservation here does not guarantee that it reaches the destination: the renderer retains or removes SGR according to [terminal capability](color-and-terminal-capability.md).

## Invalid and binary data

Invalid UTF-8 and unmappable legacy-encoding bytes become visible `\xNN` escapes. A valid multibyte character split across writes remains intact once its remaining bytes arrive.

`ASCII-8BIT` is treated as binary rather than guessed text. Printable ASCII, tab, carriage return, and newline remain readable; every other byte becomes `\xNN`. Incomplete encoded input receives the same visible treatment when capture finishes.

## Change checklist

Test input split across writes and transitions, not only complete strings, when changing sanitization:

- Split UTF-8, UTF-16, and legacy multibyte characters.
- Split, oversized, and incomplete terminal sequences.
- CRLF divided across writes.
- Binary, invalid, and unmappable bytes.
- Source encoding changes with pending state.
- Entry or source changes that force `finish`.
