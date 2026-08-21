# Rendering and attribution

`Renderer` is the only component that owns human-readable formatter output.
It keeps entry state, capture line state, styling state, and destination
encoding state in one place.

## Entry state machine

An entry starts when the renderer receives an example, context, suite, external
RSpec message, summary, profile, rerun list, or seed. Before a new entry it:

1. Finishes any open captured source line.
2. Writes exactly one blank line if an earlier entry exists.
3. Sets the new entry kind and path.

An example header, its captured output, result, rerun command, and failure are
one entry. Results and failures finish captured text and append lines to the
active example entry. Contiguous suite or context-hook output remains one entry
until a group transition, example, or RSpec-owned report section starts another
one. The renderer never uses terminal width, carriage return, cursor movement,
or line erasure.

Captured text is flushed immediately, including an unterminated partial line.
The renderer keeps a source prefix open for a partial line. A source change
first closes the old display line, then begins the new line with its own
prefix. It never puts stdout and stderr payload on the same display line.

## Paths and hooks

The formatter keeps the active example-group stack. It builds a path from the
non-empty group descriptions followed by the example description. It does not
split `full_description`, because an example description can contain the
configured separator. An empty example description falls back to its rerun
location. If the configured separator cannot be encoded by the destination,
the formatter uses ` > ` for that path.

Example output is attributed to the full path:

```text
A car › during maintenance › it disables safety guardrails
```

Example hooks stay attributed to the current example until its result event.
Group hooks run outside an active example. The formatter marks groups as seen
when an example starts and emits a context path only when earlier output has
not already made the context visible. Suite hooks use `suite stdout |` and
`suite stderr |`. If suite output is the first visible report entry, the
formatter emits `RSpec suite` first.

## Captured line labels

The source label is selected before rendering:

- `stdout` and `stderr` inside an example;
- `suite stdout` and `suite stderr` outside an example;
- `rspec` for formatter messages from RSpec itself.

Every physical captured line has two spaces, its source label, ` | `, and the
payload. A newline-terminated chunk does not leave a dangling prefix. A
partial chunk is still written immediately and is completed at the next
boundary.

## Results and timing

The formatter uses distinct statuses for passed, failed, pending, and skipped
examples. `pending` and `skipped` both contribute to the summary pending count.
An example marked pending that unexpectedly passes is delivered by RSpec as a
failure and remains failed.

The default duration threshold is 0.5 seconds. A qualifying duration appears
next to the result in milliseconds below one second and seconds with two
decimal places at or above one second. `nil` disables per-example durations.
Pending and skipped results use the same threshold logic.

Status glyphs use emoji when the destination supports them and the setting
allows it. The deterministic fallbacks are `[PASS]`, `[FAIL]`, `[PENDING]`,
and `[SKIP]`. Formatter color is enabled by default, even for non-TTY output,
unless a non-empty `NO_COLOR`, RSpec `color_mode == :off`, or formatter
configuration disables it.

## Failure and summary output

Failed examples receive their status, an inline rerun command, and the failure
details. The details come from RSpec's failure presenter, so source snippets,
filtered backtraces, aggregate failures, shared-example traces, causes, and
`extra_failure_lines` remain available. The formatter removes only a duplicate
leading full description when it can identify it safely.

The final failed-example list contains unique rerun commands. The target uses
RSpec's `location_rerun_argument` when unique and the example id when multiple
examples share a location. POSIX targets use `Shellwords.escape`. Windows
targets use `WindowsCommandLine` and account for the RubyGems batch launcher.

The summary notification is authoritative. The renderer prints total,
succeeded, failed, pending, suite duration, load time, and nonzero errors
outside examples. Succeeded is computed as `total - failed - pending` so the
example counts reconcile. Profile and random-seed sections are rendered in the
final phase when RSpec requests them.

## Styling boundaries

Captured application SGR sequences remain in the payload. The sanitizer turns
other terminal controls into visible text. The renderer writes a reset before
formatter-owned lines and at captured boundaries, so application styling does
not bleed into statuses, failures, or summaries. Formatter styling does not
change captured applications' own `NO_COLOR` behavior.
