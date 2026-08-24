# Color and terminal capability

The formatter separates a user's color preference from the destination's ability to handle ANSI Select Graphic Rendition sequences. `Renderer` applies or removes formatter styles and SGR sequences from captured application output. `WindowsTerminal` determines whether a Windows destination can display those sequences.

## Preference and capability

Formatter color is enabled only when all of these conditions hold:

- `config.color` is true.
- `NO_COLOR` is absent or empty.
- RSpec's color mode is not `:off`.
- The destination supports ANSI according to the platform policy.

On non-Windows platforms, ANSI is allowed for both terminal and redirected destinations. On Windows, redirected output also keeps ANSI styling so ANSI-aware files and CI logs preserve the configured colors. Interactive output requires a non-empty `WT_SESSION` and successful Virtual Terminal enablement; other interactive Windows consoles receive plain text.

Emoji is a separate decision. Setting `emoji` to false forces deterministic ASCII status labels. The `:auto` and true settings use a glyph only when the destination implements `external_encoding` and either reports no concrete encoding or reports one that can represent the glyph.

## Windows Terminal and Fiddle

Fiddle is a Windows-only runtime dependency used to call the console API. On Windows, users must add it to their Gemfile. It is not a gemspec dependency because the gemspec cannot express a platform-specific runtime dependency. Keep the installation instruction in the public README when changing this integration.

For interactive Windows Terminal output, `WindowsTerminal::NativeApi` obtains the stdout or stderr console handle, reads its mode, and adds `ENABLE_VIRTUAL_TERMINAL_PROCESSING` when necessary. Invalid handles, failed console calls, unavailable Fiddle APIs, and other `Fiddle::Error` failures make `WindowsTerminal` report that ANSI is unavailable, so the renderer uses plain text. Unrelated programming errors are not suppressed.

Renderer tests can receive a fake terminal-capability checker, while `NativeApi` isolates calls to `kernel32.dll`. The tests use a fake Windows API adapter to check when ANSI is allowed and how API failures are handled. They do not call the native APIs that select a console handle or read and change its mode. Verify those calls in an interactive native Windows environment when changing `NativeApi`.

## Captured application styling

The sanitizer preserves valid SGR so application styling can survive capture. When ANSI capability is unavailable, the renderer removes captured SGR along with formatter styling. When capability is available but formatter color preference is off, application SGR remains; formatter color settings do not override the application's own styling policy.

When formatter color is enabled, stdout and suite-stdout labels and unstyled payload use gray, while stderr and suite-stderr use yellow. Once a captured entry contains application SGR, the renderer stops wrapping later payload in a formatter source color for the remainder of that capture entry.

The renderer writes resets at formatter-owned and captured-content boundaries. It also resets after captured application styling even when formatter color itself is disabled. This prevents application styling from bleeding into statuses, failures, summaries, or later entries.
