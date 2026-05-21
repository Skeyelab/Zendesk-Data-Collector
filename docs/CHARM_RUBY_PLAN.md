# Charm Ruby Integration Plan

Research into how the [Charm Ruby](https://charm-ruby.dev) gem ecosystem could improve the interface, UX, and developer experience of this repo.

---

## Background

[Charm Ruby](https://charm-ruby.dev) is a set of Ruby bindings/ports of Charmbracelet's acclaimed Go terminal-UI libraries. Maintained by Marco Roth, the suite provides everything needed to build glamorous CLIs and interactive terminal UIs (TUIs) in pure Ruby. The gems are published on RubyGems and available from GitHub.

### Gem Inventory

| Gem | RubyGems name | What it does |
|-----|--------------|--------------|
| [glamour-ruby](https://github.com/marcoroth/glamour-ruby) | `glamour` | Stylesheet-based Markdown rendering in the terminal |
| [lipgloss-ruby](https://github.com/marcoroth/lipgloss-ruby) | `lipgloss` | CSS-inspired style definitions for terminal layouts (colours, borders, alignment) |
| [huh-ruby](https://github.com/marcoroth/huh-ruby) | `huh` (GitHub source) | Beautiful interactive forms, prompts, and selection menus |
| [bubbletea-ruby](https://github.com/marcoroth/bubbletea-ruby) | `bubbletea` | Elm Architecture TUI framework — build full-screen interactive apps |
| [bubbles-ruby](https://github.com/marcoroth/bubbles-ruby) | `bubbles` | Pre-built TUI components (spinners, progress bars, lists, viewports) |
| [ntcharts-ruby](https://github.com/marcoroth/ntcharts-ruby) | `ntcharts` | Terminal sparklines, bar charts, and line graphs |
| [gum-ruby](https://github.com/marcoroth/gum-ruby) | `gum` | Scripting-friendly wrapper for Charm's Gum binary |
| [harmonica-ruby](https://github.com/marcoroth/harmonica-ruby) | `harmonica` | Physics-based spring animations |
| [bubblezone-ruby](https://github.com/marcoroth/bubblezone-ruby) | `bubblezone` | Mouse zone tracking for Bubble Tea apps |
| [minitest-bubbletea](https://github.com/marcoroth/minitest-bubbletea) | `minitest-bubbletea` | TUI reporter for Minitest test runs |

---

## Current State — Where The DX Hurts

| Area | Current experience |
|------|--------------------|
| `rake queue:stuck / stats / failed` | Plain `puts` output; styled only with raw emoji and dashes |
| `rake queue:cleanup_stuck` | No progress feedback; silent until done |
| No developer onboarding wizard | New contributors must read DEPLOYMENT.md manually and generate keys by hand |
| Minitest output | Default dot-matrix reporter; hard to scan during long runs |
| No in-terminal docs | README/DEPLOYMENT.md only readable outside the terminal session |
| No live queue monitoring | Must refresh Mission Control web UI or re-run rake tasks manually |

---

## Proposed Implementation Tickets

### Ticket 1 — Beautify Rake task output with `lipgloss`

**Gem:** `lipgloss`  
**Effort:** Small (1–2 days)  
**Value:** Immediate improvement every time a developer runs a rake task

Refactor `lib/tasks/queue.rake` to use Lipgloss styles instead of raw `puts` strings. Specific improvements:

- Boxed section headers with rounded borders and a purple accent colour
- Colour-coded job counts (green = healthy, yellow = warning, red = problem)
- A styled summary table at the end of `rake queue:stats` using `Lipgloss::Table`
- Indented, dimmed detail rows vs. bold headline counts

**Acceptance criteria:** Running `rake queue:stuck`, `rake queue:stats`, and `rake queue:failed` produces visually distinct, easy-to-scan output with no changes to the underlying logic.

---

### Ticket 2 — In-terminal documentation viewer with `glamour`

**Gem:** `glamour`  
**Effort:** Small (< 1 day)  
**Value:** Reduces context-switching; developers can read docs without leaving the terminal

Add a `rake docs[section]` task (and a thin `bin/docs` binstub) that renders Markdown files to the terminal with `Glamour.render`. Priority docs to expose:

- `README.md` — full overview
- `DEPLOYMENT.md` — production setup steps
- `docs/WEBHOOK_API.md` — webhook reference

Example usage:
```
rake docs             # renders README
rake docs[deployment] # renders DEPLOYMENT.md
rake docs[webhook]    # renders WEBHOOK_API.md
```

**Acceptance criteria:** `rake docs` outputs the README with styled headings, code blocks highlighted, and tables formatted — auto-detecting the terminal's light/dark theme.

---

### Ticket 3 — Interactive desk-setup wizard with `huh`

**Gem:** `huh`  
**Effort:** Medium (2–3 days)  
**Value:** Eliminates manual data entry errors when configuring a new Zendesk account

Add a `rake desk:wizard` (or `bin/setup-desk`) interactive task that walks a user through creating a new `Desk` record using `Huh` forms:

1. **Step 1 — Identity**: Subdomain input with format validation (`*.zendesk.com`)
2. **Step 2 — Credentials**: API token input with password echo mode and a validate-on-submit check against the live Zendesk API
3. **Step 3 — Options**: Multi-select for `fetch_comments` / `fetch_metrics` toggles
4. **Step 4 — Confirmation**: Review note before persisting

**Acceptance criteria:** `rake desk:wizard` creates a valid `Desk` record without touching the Avo web UI; bad input is rejected inline with friendly error messages.

---

### Ticket 4 — Developer onboarding wizard with `huh` + `glamour`

**Gem:** `huh`, `glamour`  
**Effort:** Medium (2–3 days)  
**Value:** Reduces time-to-first-run for new contributors from "read a long doc" to < 5 minutes

Enhance `bin/setup` with an interactive first-run flow:

1. Render a welcome banner using `Glamour`
2. Detect missing `.env` / credentials and prompt for them interactively with `Huh`
3. Auto-generate `ACTIVE_RECORD_ENCRYPTION_*` keys and write them to `.env`
4. `Huh.spinner` wrapper around `bundle install` / `db:create` / `db:migrate`
5. Show a styled success summary with next steps rendered via `Glamour`

**Acceptance criteria:** A developer who clones the repo and runs `bin/setup` has a running development environment without manually reading any documentation.

---

### Ticket 5 — Live queue monitoring TUI with `bubbletea` + `bubbles` + `ntcharts`

**Gems:** `bubbletea`, `bubbles`, `ntcharts`  
**Effort:** Large (1–2 weeks)  
**Value:** Replaces repeated `rake queue:stuck` polling with a real-time dashboard

Build a `bin/monitor` command (inspired by the [proc-tui Charm Ruby demo](https://github.com/Charm-Ruby/demos/tree/main/proc-tui)) that displays a full-screen TUI with:

- **Header row**: Active worker count, last-refresh timestamp
- **Status panel** (left): Live counts for ready / claimed / blocked / failed / scheduled jobs, colour-coded
- **Chart panel** (right): `ntcharts` sparkline of job throughput over the last 60 seconds
- **Detail table** (bottom): Last 10 failed jobs with class name, queue, and truncated error — scrollable viewport
- **Controls**: `r` to manually refresh, `c` to trigger `cleanup_stuck`, `q` to quit

Auto-refreshes every 5 seconds using a Bubble Tea tick command.

**Acceptance criteria:** `bin/monitor` launches without a Rails server and updates in real-time; pressing `c` calls `SolidQueue` cleanup and displays a confirmation notice.

---

### Ticket 6 — Beautiful Minitest reporter with `minitest-bubbletea`

**Gem:** `minitest-bubbletea`  
**Effort:** Small (< 1 day)  
**Value:** Instant ergonomic improvement for every test run

Add `minitest-bubbletea` to the `:test` group in `Gemfile` and configure it as the default reporter in `test/test_helper.rb`.

The TUI reporter provides:
- Live pass/fail/skip counts that update as tests run
- A collapsible failures panel
- Final summary with timing and coverage link

**Acceptance criteria:** `bundle exec rails test` renders the Bubble Tea reporter instead of the default dot matrix output; existing SimpleCov integration continues to work.

---

### Ticket 7 — Add terminal charts to `rake queue:stats` with `ntcharts`

**Gem:** `ntcharts`  
**Effort:** Small (1 day)  
**Value:** Makes job-count data scannable at a glance; no separate dashboard needed for basic monitoring

Extend `rake queue:stats` to append a bar-chart breakdown of unfinished jobs by queue and by class name using `ntcharts`. The chart replaces the current plain-text list and makes relative queue depths immediately visible.

**Acceptance criteria:** `rake queue:stats` outputs a horizontal bar chart of queue depths below the existing summary text, with no changes to the text summary itself.

---

## Suggested Rollout Order

| Priority | Ticket | Rationale |
|----------|--------|-----------|
| 1 | Ticket 6 — Minitest reporter | Zero-risk drop-in; pays off every test run immediately |
| 2 | Ticket 1 — Rake output styling | Low-risk refactor of existing tasks; high daily visibility |
| 3 | Ticket 2 — Docs viewer | One-file addition; immediate value for new contributors |
| 4 | Ticket 7 — Queue charts | Extends an existing task with visual data |
| 5 | Ticket 4 — Onboarding wizard | Requires `bin/setup` changes; medium risk |
| 6 | Ticket 3 — Desk wizard | New capability; medium-effort rake task |
| 7 | Ticket 5 — Live monitor TUI | Largest effort; best saved for after smaller wins validate the gems in this stack |

---

## Maturity Notes

- **glamour, lipgloss**: Both actively maintained, published to RubyGems, used in production OSS projects. Safe to add now.
- **huh**: Available from GitHub only (no RubyGems release yet); use `gem "huh", github: "marcoroth/huh-ruby"`. Treat as beta — pin to a specific commit SHA for stability.
- **bubbletea, bubbles, ntcharts**: Under active development. Recommend pinning to a commit SHA and adding an integration smoke test in CI before shipping Ticket 5.
- **minitest-bubbletea**: Early-stage; verify it supports `parallelize(workers: :number)` before enabling (important given the existing `coverage.rake` parallel-merge setup).
- All gems are MIT-licensed and have no native extensions — they wrap Go binaries via FFI or shell-out.

---

## References

- Charm Ruby home: <https://charm-ruby.dev>
- Charm Ruby demos (including proc-tui): <https://github.com/Charm-Ruby/demos>
- marcoroth/glamour-ruby: <https://github.com/marcoroth/glamour-ruby>
- marcoroth/lipgloss-ruby: <https://github.com/marcoroth/lipgloss-ruby>
- marcoroth/huh-ruby: <https://github.com/marcoroth/huh-ruby>
- marcoroth/bubbletea-ruby: <https://github.com/marcoroth/bubbletea-ruby>
- marcoroth/ntcharts-ruby: <https://github.com/marcoroth/ntcharts-ruby>
- marcoroth/minitest-bubbletea: <https://github.com/marcoroth/minitest-bubbletea>
