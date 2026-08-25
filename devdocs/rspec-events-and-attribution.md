# RSpec events and attribution

`RSpec::CapturingFormatter` converts RSpec notifications and captured writes into requests to build the report. It decides which example or surrounding context receives each write, interprets RSpec result data, and tells `Renderer` which final report sections to produce. `Renderer` only decides how those requests appear; see [Report model and rendering](report-model-and-rendering.md).

## Notification phases

The formatter registers only the notifications needed for group tracking, example results, RSpec messages, shutdown, and requested final sections. It deliberately omits `dump_failures` and `dump_pending` because failure and expected-pending details are rendered inline with their examples. Registering the dump notifications would duplicate those details. RSpec's separate deprecation formatter remains responsible for deprecations.

`start` records planned count and load time when the notification provides them, but does not reset renderer state. Captured output, messages, or a seed notification may already have arrived. Group and example notifications then maintain attribution during the run.

RSpec sends `stop` after `after(:suite)`. The formatter deactivates capture at that point so late threads and `at_exit` code pass through without formatter attribution. The renderer remains usable because RSpec can request profiles, summaries, seed output, and close after capture has stopped.

## Example and hook attribution

The formatter builds paths from the active example-group stack instead of splitting `Example#full_description`. Group and example descriptions can contain the configured separator, so paths use each description as a separate part. Empty group descriptions are omitted, and an empty example description falls back to its rerun argument. If the destination declares an external encoding that cannot represent the configured separator, path construction uses `>`.

An example becomes current at `example_started` and remains current through its result notification. Output from example hooks is therefore attributed to that example. Group hooks run without a current example and use the active group path. The formatter records which group headings it has already printed, so output outside an example prints the current group's heading only if that heading has not appeared yet. Output outside any group uses suite labels and emits `RSpec suite` when it is the first visible report content.

Because attribution follows current formatter state rather than thread origin, same-process parallel examples cannot be attributed reliably. Threads are synchronized, but a late write belongs to the state active when the manager handles it, not necessarily to the example whose code created the thread.

## RSpec messages

The `message` notification is RSpec-owned report content rather than application stdout or stderr. Outside an example it starts an `rspec |` entry. Inside an example its lines remain under the current entry, and later application output resumes with its stdout or stderr label.

## Results and failures

RSpec supplies distinct passed, failed, and pending notifications. A pending notification with no pending exception is treated as skipped. An example marked pending that unexpectedly passes arrives as failed and remains a failure. The summary notification is authoritative for final counts; succeeded is derived as total minus failed minus pending so the displayed example counts reconcile.

RSpec may provide formatted failure details for an expected pending example. The formatter's `pending_failure_output` setting controls how much of that output is shown; when it is unset, the formatter follows RSpec's setting if that API is available. Full mode keeps the lines returned by RSpec, no-backtrace mode removes lines whose stripped content starts with `# `, and skip mode does not request expected-failure details. This setting does not reconfigure RSpec's presenter, so formatter `:full` cannot restore backtrace lines that RSpec has already omitted.

For failures, the formatter asks the notification for `fully_formatted_lines` and supplies its own colorizer when supported. This preserves RSpec's source extraction, filtered backtraces, aggregate failures, shared-example traces, causes, and extra failure lines. Older RSpec APIs may not accept a colorizer. In that case, the formatter uses the available message lines or calls the presenter without one. When it uses `fully_formatted_lines`, it removes the first line only if that line exactly matches the example's full description after ANSI codes are removed.

## Final report requests

The summary notification supplies final counts, suite duration, load time, and errors outside examples. The renderer emits the summary, unique failed reruns, and the stored seed when random ordering was actually used. Errors outside examples are reported separately and do not increase the example total.

Profiles are rendered only when RSpec requests them. Some RSpec versions omit the slow-examples or slow-groups field from profile notifications. The formatter accepts those versions and prints a visible no-examples line when both lists are absent or empty.

RSpec 3.12, 3.13, and the maintained 4.0 prerelease differ in some notification and presenter APIs. Keep capability checks local to event interpretation rather than branching the renderer by RSpec version, and follow [Testing and compatibility](testing-and-compatibility.md) when changing these calls.
