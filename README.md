# Jenbach

Lightweight statusline HUD and usage/cost reporting tool for **Google Antigravity CLI (`agy`)**.

**Live Statusline HUD**
<p align="left">
  <img src="https://github.com/user-attachments/assets/16785252-2712-44a9-bc7a-3d7e7581663d" alt="Jenbach live statusline HUD" width="820">
</p>

**Usage & Subagent Report (`jenbach` / `!jenbach`)**

<p align="left">
  <img src="https://github.com/user-attachments/assets/71783481-48e7-44e1-9525-683d55c3ebae" alt="Jenbach usage and subagent report" width="820">
</p

## Features

- **Live Statusline:** Track your active model, token usage, cache hit rate, context fill, estimated cost (including live per-subagent spend and animated activity spinner), and remaining weekly quota directly inside `agy`—automatically adapting to your terminal width.
- **Zero-Token Usage Reports:** Run `!jenbach` inside `agy` (spends 0 tokens) or `jenbach` in your terminal for an instant summary of your spend and session history, including a per-subagent tree view (`split` or `combined` mode).
- **Customizable Look:** Switch between `modern`, `compact`, and `plain` themes with automatic color support (`NO_COLOR` friendly).
- **Automatic Price Updates:** Model pricing stays up to date automatically in the background—no manual maintenance required.
- **Works Everywhere:** Keeps any existing `agy` statusline plugin working alongside Jenbach. Supports Linux, macOS, WSL, and Windows (Git Bash). Requirements: `bash`, `jq` (optional: `python3` for live subagent DB sync, `curl` for automatic price updates).

## Installation

Run in your terminal (**Git Bash** on Windows):

~~~bash
git clone https://github.com/utariddev/jenbach.git
cd jenbach
chmod +x install.sh && ./install.sh
~~~

> **PATH Note:**
> - **macOS / Linux:** `install.sh` links `jenbach` into `~/.local/bin`, `/usr/local/bin`, and `/opt/homebrew/bin` (when writable). If `jenbach` is still not found in your terminal, add `export PATH="$HOME/.local/bin:$PATH"` to your `~/.zshrc` or `~/.bashrc`.
> - **Windows:** Add `%USERPROFILE%\bin` (`$HOME/bin`) and `jq` to your Windows `PATH` to run `jenbach` from Git Bash, PowerShell, or CMD.

## Usage

All commands work both **inside `agy`** (`!jenbach ...`) and **directly in your terminal** (`jenbach ...`) on Linux, macOS, WSL, and Windows:

- Usage report (defaults to current week (Mon-Sun)): `jenbach` (or `!jenbach` inside `agy`)
- Interactive settings (terminal): `jenbach config`
- Project info & version: `jenbach info` (or `jenbach --version`)
- Help: `jenbach --help` (or `!jenbach help`)

<p align="left">
  <img src="https://github.com/user-attachments/assets/ad57ae94-0688-4e99-b82c-725a566c2b26" alt="Jenbach settings menu" width="560">
</p>

### Report Views & Date Filters

| Command | Description |
| --- | --- |
| `!jenbach` | Show report using `default_view` (`week` by default, or `today`, `month`, `all`) |
| `!jenbach all` | Show all recorded sessions regardless of date |
| `!jenbach today` | Show sessions recorded today |
| `!jenbach week [#]` | Show calendar week (Mon–Sun; optional `#` = weeks ago, default `0`) |
| `!jenbach weeks` | Show weekly usage summary table |
| `!jenbach month [#\|YYYY-MM]` | Show calendar month (optional `#` = months ago, default `0`, or `YYYY-MM`) |
| `!jenbach --month YYYY-MM` | Show sessions from a specific month |
| `!jenbach --from <DATE\|DATETIME> [--to <DATE\|DATETIME>]` | Show sessions within a date/datetime range (`YYYY-MM-DD[ HH:MM]`) |
| `!jenbach [view] -n <N>` / `--limit <N>` | Override `history_limit` for one run and disable height auto-fit |

### Quick Commands

| Command | Description |
| --- | --- |
| `!jenbach set short [on\|off]` | Format report token counts in short form (e.g. `1736` → `1.7k`) |
| `!jenbach set status-short [on\|off]` | Format live statusline token counts in short form |
| `!jenbach set history [on\|off]` | Show or hide the recent sessions table in reports |
| `!jenbach set limit <N>` | Set how many recent sessions to display (`N >= 1`) |
| `!jenbach set chain [on\|off\|clear]` | Toggle or remove a chained statusline plugin |
| `!jenbach set theme [modern\|compact\|plain]` | Switch UI style (`modern`, `compact`, or `plain`) |
| `!jenbach set color [auto\|on\|off]` | Control terminal color output |
| `!jenbach set auto-update [on\|off]` | Enable or disable automatic background price checks |
| `!jenbach set check-interval <1..720>` | Set how often (in hours) prices are checked automatically |
| `!jenbach set check-updates [on\|off]` | Enable or disable automatic background app update checks |
| `!jenbach set default-view [week\|today\|month\|all]` | Set the default report view for `!jenbach` |
| `!jenbach set subagent-mode [split\|combined]` | Show subagents as tree rows (`split`) or merged into parent (`combined`) |
| `!jenbach set status-sub [on\|off]` | Show or hide `(Sub: $...)` detail in the statusline |
| `!jenbach set auto-fit [on\|off]` | Auto-fit recent sessions table to terminal height |
| `!jenbach info` | Show version, GitHub URL, paths, pricing status, and environment |
| `!jenbach --version` | Print installed Jenbach version |
| `!jenbach prices` | View current model pricing per 1M tokens |
| `!jenbach update [--force]` | Update Jenbach to the latest GitHub release |
| `!jenbach update-prices [url]` | Refresh model prices immediately (optionally from a custom URL) |
| `!jenbach reset` | Delete all recorded session logs |

### Environment Variables

| Variable | Description |
| --- | --- |
| `NO_COLOR=1` | Disable ANSI color output in both statusline and usage reports |
| `JENBACH_WIDTH=<cols>` | Override detected terminal column width for report tables |
| `JENBACH_HEIGHT=<rows>` | Override detected terminal row height for session history auto-fit (`0` disables height limit) |

## Updating

Jenbach checks GitHub Releases in the background (once every 24 hours) and shows a passive banner in `jenbach` and `jenbach info` when a newer version is available.

To update to the latest release, run:

~~~bash
jenbach update
~~~

Or inside `agy`:

~~~text
!jenbach update
~~~

Use `jenbach update --force` to reinstall the latest release even if you are already on the same version. All user settings (`report_config.json`) and recorded session logs (`usage_logs`) are preserved.

## Uninstallation

~~~bash
chmod +x uninstall.sh && ./uninstall.sh
~~~

To also delete all recorded session logs (`usage_logs`):

~~~bash
./uninstall.sh --purge
~~~

---

*Named after the peaceful town of Jenbach.*
