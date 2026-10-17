# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [3.1.2] — test.sh no longer kills your real monitors

### Fixed
- `cache-keepalive-ctl.sh off-all` and `status` found monitors by scanning
  every process on the machine, so `test.sh` (which runs `off-all` against
  its own throwaway `CCKA_STATE_DIR`) killed the user's real monitors; Claude
  Code then woke each affected session with a "monitor ended" notification.
  On Linux the scan now only matches monitors whose `CCKA_STATE_DIR` (read
  from `/proc/<pid>/environ`, default `~/.claude/cache-keepalive`) is the
  ctl's own. With the default state dir nothing changes for normal use.

### Tests
- `off-all` leaves a monitor of another state dir running. Tests 79 -> 80.

## [3.1.1] — make the 12 h max-idle cap actually stop pinging

### Fixed
- `CCKA_MAX_IDLE_SECONDS` never triggered. Every ping is a turn, and its
  `Stop` (and `UserPromptSubmit`, which Claude Code also fires for task
  notifications) reset the heartbeat the cap was measured from, so an
  abandoned session pinged every ~50 min indefinitely; one real session pinged
  50 times over 45 hours without a single prompt. The cap is now measured from
  `last_prompt.<session>`, which the `UserPromptSubmit` hook (`stamp.sh
  --prompt`) writes only for a prompt that is not a `<task-notification>`.
  Starting or resuming a session also restarts it. The 50-minute heartbeat
  logic is unchanged.

### Tests
- Prompt vs task-notification stamping, and a simulated session that answers
  every ping with `UserPromptSubmit` + `Stop` still hits the cap. Tests 74 -> 79.

## [3.1.0] — keep the monitor across /resume and /clear

### Fixed
- Resuming a session no longer wakes it up. `/resume` (and `/clear`) fire
  `SessionEnd` with reason `resume`/`clear` inside the same Claude Code
  process; the cleanup hook killed the monitor, and Claude Code delivered its
  "monitor ended" notification to the resumed session, which started a full
  cold-cache turn before you typed anything. The cleanup now leaves the
  monitor running for those reasons and stops it only on a real exit.
- The monitor keeps working after `/resume` and `/clear`. Claude Code arms a
  plugin monitor once per process, so after a switch none was running. A new
  `SessionStart` hook records which session the process is showing in
  `host.<CLAUDE_PID>`, and the monitor follows it on its next tick (its pid
  file moves with it, so `SessionEnd` and the ctl script still find it). A
  switch is treated like a fresh start: a stale heartbeat is reset to now, so
  the first ping comes one idle window after the resume.

### Changed
- The per-session `disabled.<session>` marker no longer stops the monitor
  from starting; it keeps it silent while that session is shown, so a later
  switch to another session still gets keepalive pings.

### Tests
- `test.sh` unsets `CLAUDE_SESSION_ID` / `CLAUDE_CODE_SESSION_ID` before
  running. Inside a Claude Code session the stamp hook picked up the real
  session id instead of the test's stdin `session_id`, failing 5 heartbeat
  tests. It also unsets `CLAUDE_PID`.
- New coverage for the session switch on `/resume` and for pruning
  `host.<pid>` files. Tests 60 -> 74.

## [3.0.2] — new maintainer, new marketplace

### Changed
- Maintenance moved to
  [JillVernus/claude-code-cache-keepalive](https://github.com/JillVernus/claude-code-cache-keepalive).
  The marketplace is renamed from `claude-cache-tools` to `jillvernus-plugins`,
  and `plugin.json` now points its author, homepage, and repository at the new
  repo. No runtime changes.
- The READMEs credit the original author and name the new maintainer.
- `LICENSE` adds a copyright line for the new maintainer; the original notice
  is kept.

### Removed
- The LINUX DO community badge and the Friends section from both READMEs.

### Migrating from the original marketplace
Remove the old install first, or both copies run their hooks and Monitors:

```
/plugin uninstall cache-keepalive@claude-cache-tools
/plugin marketplace remove claude-cache-tools
/plugin marketplace add JillVernus/claude-code-cache-keepalive
/plugin install cache-keepalive@jillvernus-plugins
```

## [3.0.1] — drop leftover references to removed skills

### Fixed
- `cache-keepalive-ctl.sh` printed re-arm hints for the removed
  `/cache-keepalive:on` and `/cache-keepalive:on-all` commands. It now says to
  run the script itself with `on` / `on-all`, and the Monitor-tool hint uses
  the script's real path instead of a `<plugin>` placeholder.
- `cache-keepalive-monitor.sh` comments and the disabled-marker log line no
  longer mention `:on`.

### Removed
- The plain-`settings.json` install route: `install.sh`, `uninstall.sh`, the
  `.gitignore` backup pattern, and the README section describing it. It predated
  the plugin, shipped only part of the runtime (no ctl/housekeeping/SessionEnd
  cleanup), and could not auto-start the monitor. Install through the plugin
  marketplace instead.
- Undocumented `cache-keepalive-ctl.sh` aliases (`on-here`, `off-this`,
  `on-everywhere`, …); only `status|on|off|on-all|off-all` remain.

### Tests
- A regression test asserts no ctl subcommand's output advertises a removed
  `/cache-keepalive:` command. Tests 59 -> 60.

## [3.0.0] — trim the command surface to manual off/status

### Changed (breaking)
- Removed the `/cache-keepalive:on`, `/cache-keepalive:on-all`, and
  `/cache-keepalive:off-all` skills. Only `/cache-keepalive:off` and
  `/cache-keepalive:status` remain. The full control set is still available in
  `cache-keepalive-ctl.sh` (`status|on|off|on-all|off-all`), and the on-disk
  markers (`disabled`, `disabled.<session>`, `CCKA_ENABLED`) stay the single
  source of truth the monitor reads — the commands only flip them.
- Both remaining skills set `disable-model-invocation: true`, so Claude no
  longer lists or auto-loads them. They are manual controls and should not sit
  in the model's context.
- Both skills now call the bundled script through `${CLAUDE_PLUGIN_ROOT}`
  instead of a cache-path glob plus a duplicated inline fallback. That fallback
  was dead code when the plugin was installed, and it had reintroduced the
  `pgrep -f` substring match fixed in 2.7.2. Tests 57 -> 59.

## [2.7.3] — bland default ping text

### Changed
- The default `CCKA_PING_TEXT` announced the mechanism ("cache keepalive:
  this session has been idle; reply with a single word so the prompt cache
  stays warm."), which landed in every transcript and read like a real user
  message. It is now `Reply with "ok" and nothing else.` — it never names the
  plugin and pins the answer to one short token, so the keepalive turn stays
  as small and as unobtrusive as possible. Tests add coverage for the default
  text (bland, short, asks for `ok`): 53 -> 57.

## [2.7.2] — find monitor processes by argv, not by substring

### Fixed
- `cache-keepalive-ctl.sh` located running monitors with `pgrep -f
  cache-keepalive-monitor.sh`, which matches the whole command line. Any
  unrelated process that merely *mentions* the script name (an editor open on
  it, a shell running a command containing the path) was matched: `status`
  showed false positives and `off-all` would **kill** them. It now matches
  argv precisely (a shell whose argument is the script; `/proc` on Linux, a
  `ps` pattern elsewhere). Tests add a decoy that mentions the name.

## [2.7.1] — pass the session id to the monitor explicitly

### Fixed
- The plugin monitor relied on `CLAUDE_SESSION_ID` being present in its
  process environment. It is not: Claude Code only substitutes
  `${CLAUDE_SESSION_ID}` **inside configured command strings**; it is not
  exported to subprocesses (anthropics/claude-code#47018, #25642). Every
  monitor therefore fell back to the shared `global` heartbeat and the
  per-session timers were inert. `monitors.json` now passes
  `--session "${CLAUDE_SESSION_ID}"`, and the monitor accepts `--session <id>`
  (still falling back to the environment).

## [2.7.0] — session-scoped opt-out

### Changed
- `on` / `off` are now **session-scoped** by default: `/cache-keepalive:off`
  stops only the current session's monitor and writes
  `disabled.<session>`, leaving other open sessions and every future session
  alone. `/cache-keepalive:on` clears it.
- The previous global behaviour moved to new `/cache-keepalive:on-all` /
  `/cache-keepalive:off-all` skills and `cache-keepalive-ctl.sh on-all |
  off-all`. `off-all` writes the global `disabled` marker; `on-all` clears the
  global marker and every per-session marker.
- `cache-keepalive-ctl.sh status` now always prints `this session` and
  `session off`, plus the session's monitor pid when one is running.

### Added
- The ctl/status scripts resolve "this session" from `CLAUDE_SESSION_ID`, then
  `CLAUDE_CODE_SESSION_ID`, then `~/.claude/cache-keepalive/last_session`
  (written by the stamp hook), so a session-scoped command targets the right
  session even when the Bash tool does not inherit the session env.

## [2.6.0] — explicit on/off control

### Added
- `/cache-keepalive:off` (and `:on`, `:status`) skills, plus
  `scripts/cache-keepalive-ctl.sh status|on|off`.
- The monitor now honours opt-out markers on every start: a global
  `disabled` file, a per-session `disabled.<session>` file, and a per-project
  `<project>/.claude/cache-keepalive-off`. Together with `CCKA_ENABLED=0` this
  means a manual stop is remembered instead of being silently undone by a
  plugin reload or the next session.

### Why
- Deleting the monitor from Claude Code's task list used to be a one-way door,
  and `/reload-plugins` would quietly bring it back. State was consistent
  either way, but the user's intent was not respected.

## [2.5.0] — idle cap + correct subscription positioning

### Added
- `CCKA_MAX_IDLE_SECONDS` (default 43200 = 12 h): the monitor stops pinging
  once a session has been idle that long, so an abandoned session no longer
  pings every idle window and burns usage. Real activity resumes pinging.
- A separate `last_ping.<session>` marker distinguishes "last real activity"
  from "last ping", so the cap is measured from genuine activity.

### Changed
- Docs: corrected positioning. Claude Pro/Max subscriptions get a **1-hour**
  prompt-cache TTL for the main conversation (within plan usage), so the
  defaults are aimed at subscribers; API keys default to a 5-minute TTL. The
  plugin is for **official Anthropic only** (Monitor is first-party).

## [2.4.0] — housekeeping

### Added
- `cache-keepalive-housekeep.sh`: at session start (throttled by
  `CCKA_HOUSEKEEP_INTERVAL`, default 6h), delete dead `monitor.*.pid` files and
  bundle per-session heartbeats/logs older than `CCKA_RETENTION_DAYS`
  (default 7) into `archive/cache-keepalive-<date>.tar.gz`, bucketed by the
  file's last-modified date. Optional `CCKA_ARCHIVE_KEEP_DAYS` pruning.
- Config: `CCKA_RETENTION_DAYS`, `CCKA_ARCHIVE_KEEP_DAYS`, `CCKA_ARCHIVE_DIR`,
  `CCKA_HOUSEKEEP_INTERVAL`.

## [2.3.0] — robust resume

### Fixed
- On startup the monitor resets an already-expired heartbeat to "now", so
  resuming a session days later no longer fires an immediate, pointless ping
  against a cold cache.
- SessionEnd cleanup now kills a pid only if its command line matches the
  monitor, so a stale `monitor.*.pid` pointing at a reused pid cannot kill an
  unrelated process.

## [2.2.0] — clean exit

### Added
- `cache-keepalive-cleanup.sh` (`SessionEnd`): stop this session's monitor
  during teardown.

### Fixed
- The monitor's wait is now a background `sleep` + `wait`, so a `SIGTERM`
  from the cleanup hook is handled immediately instead of being deferred until
  the foreground `sleep` returned.

## [2.1.0] — per-session timers

### Changed
- Heartbeat and log are keyed by `CLAUDE_SESSION_ID`
  (`last_stop.<session>`, `cache-keepalive.<session>.log`), so concurrent
  sessions keep independent idle timers instead of sharing one global clock.
- Falls back to the shared `last_stop` when no session id is visible.

## [2.0.0] — Monitor-based idle timer

### Changed (breaking)
- Replaced the sleeping `Stop` hook with a resettable idle timer: the hook only
  stamps activity, and a background **Monitor** pings once the session has been
  idle for `CCKA_IDLE_SECONDS`.
- No UI blocking, no 8-consecutive-block cap, supports ~50-minute waits.
- Removed the old `cache-keepalive-stop.sh` / `cache-keepalive-reset.sh` and
  the stale plugin `userConfig`.
- `install.sh` migrates old wiring; `uninstall.sh` removes the new scripts.

## [1.0.0] — initial

- `Stop` hook that sleeps and returns `decision: "block"` to keep the prompt
  cache warm; per-session counters; installer, uninstaller and tests.
