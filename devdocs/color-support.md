# Color support

The formatter uses ANSI Select Graphic Rendition (SGR) sequences for formatter-owned colors and emphasis. It does not use a colorization gem. Keeping the sequences in the renderer preserves styling boundaries and lets captured application output retain its own SGR sequences when the destination supports them.

## Capability policy

Color preference and ANSI capability are separate decisions.

- `config.color = false` disables formatter colors.
- A non-empty `NO_COLOR` disables formatter colors.
- RSpec `--no-color` disables formatter colors.
- On Unix, ANSI output remains available when the formatter color preference enables it.
- On Windows redirected output keeps the existing ANSI report behavior for logs and files.
- On Windows interactive output is supported in Windows Terminal, identified by `WT_SESSION`, when the console accepts Virtual Terminal processing.
- Legacy Windows console sessions are not a supported color target. They receive plain text instead of literal escape sequences.

Windows Terminal support uses the Windows console API through the `fiddle` runtime dependency. The formatter enables `ENABLE_VIRTUAL_TERMINAL_PROCESSING` for the destination handle. A missing API, an unavailable handle, or a failed mode change is a safe plain-text fallback. Fiddle API-loading errors use the same fallback; unrelated programming errors are not hidden.

The formatter does not change the application's `NO_COLOR` behavior. It only removes captured SGR when the report destination cannot render ANSI. Other terminal controls have already been made visible by the [sanitizer](sanitization-and-encoding.md).

## Rendering boundaries

The [renderer](rendering-and-attribution.md) applies its capability decision to headers, statuses, source labels, summaries, and RSpec failure presenter output. It writes resets around formatter-owned boundaries so captured styling cannot bleed into the report.

When ANSI is supported, captured SGR remains in the payload. When ANSI is unsupported, captured SGR is removed while ordinary captured text and report prefixes remain unchanged. This applies to complete SGR sequences after the sanitizer has resolved sequences split across writes.

## Testing

The platform decision is injected into renderer unit tests, so unsupported-console behavior is tested on every development platform. The Windows adapter has separate tests for non-Windows output, redirected output, legacy consoles, Windows Terminal, and failed VT enablement. Native Windows CI is required for validating the actual console API and Windows Terminal environment.
