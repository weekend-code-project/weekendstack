# WeekendStack Setup Script — Formatting Rules

This document is the source of truth for all terminal output formatting in the
setup script. Update this file any time a rule changes, then make sure all
scripts follow it.

---

## Screen Structure

Every distinct step or phase follows this structure:

```
(blank line emitted by log_header)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Screen Title
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
(blank line emitted by log_header)

  (content)

```

Always use `log_header "Title"` — never replicate the ━━━ block manually.

---

## Status Icons

All status output must go through the shared log functions defined in
`tools/setup/lib/common.sh`. **Never** `echo` an icon character directly.

| Function       | Icon | Colour | Use for                                      |
|----------------|------|--------|----------------------------------------------|
| `log_step`     | →    | Cyan   | An action currently in progress               |
| `log_success`  | ✓    | Green  | A confirmed success or completed check        |
| `log_info`     | ℹ    | Blue   | Neutral information (counts, discovered values) |
| `log_warn`     | ⚠    | Yellow | Something unexpected; setup continues         |
| `log_error`    | ✗    | Red    | A hard failure; usually followed by `exit 1` |

All functions indent output by 2 spaces so icons align with bullet points.

```bash
# Correct
log_success "API token is valid"
log_warn "init-filebrowser.sh: could not be created — permission denied"

# Wrong — bypasses colour and alignment
echo "  ✓ API token is valid"
echo "⚠ something happened"
```

---

## Bullet Lists

Use plain `echo` with `  •` (2 spaces + bullet) for unordered list items.
These are for descriptive/informational lists, not status outcomes.

```bash
echo "  • Docker Hub (rate limited):   $dockerhub_count images"
echo "  • GitHub Container Registry:   $ghcr_count images"
```

The 2-space indent keeps bullets visually aligned with log function icons.

---

## Sub-Section Labels (within a screen)

Use `echo -e "${BOLD}Label:${NC}"` for bold inline labels that group content
within a single screen. These are **not** the same as a screen title — do not
use `log_header` for them.

```bash
echo -e "${BOLD}Access:${NC}"
echo "  Base IP: $host_ip"
echo ""
echo -e "${BOLD}Documentation:${NC}"
echo "  • Setup summary: SETUP_SUMMARY.md"
```

---

## Tables

Two-column tables use `printf` for alignment. Do **not** add a `---` separator
row — use a blank line between the header and data instead.

```bash
printf "  %-25s %s\n" "SERVICE" "PORT"
echo ""
printf "  %-25s %s\n" "glance" "8080"
printf "  %-25s %s\n" "coder"  "7080"
```

---

## Press-Enter Pauses

Use this exact pattern for pauses after informational screens:

```bash
echo ""
read -rp "  Press Enter to continue..." || true
```

The `|| true` prevents a non-zero exit if stdin is unavailable
(e.g. during automated testing).

---

## Yes/No Prompts

Always use `prompt_yes_no` from `common.sh`. Never use raw `read -p "[y/N]:"`.

```bash
# Default yes
if prompt_yes_no "Keep existing configuration?" "y"; then ...

# Default no
if prompt_yes_no "Enable GPU support?" "n"; then ...
```

The function handles `[Y/n]` / `[y/N]` display automatically.

---

## Menus

Use `prompt_select` from `common.sh`. Menu rules:
- Option 1 is always **None / Skip** on any opt-in menu.
- Verb is always **Select:**
- Default printed as `[N]:` where N is the option number.

```bash
local choice
choice=$(prompt_select "Select:" \
    "1) None   — skip this step" \
    "2) Whisper — speech-to-text" \
    "3) LocalAI — local OpenAI API")
```

---

## Forbidden Patterns

These must never appear in terminal output:

| Pattern | Reason |
|---------|--------|
| `╔ ╠ ╚ ║ ═ ╗ ╝` | Old box-drawing style — replaced by ━━━ headers |
| `=== Title ===` | Old section divider — use `log_header` |
| `echo "  ✓ ..."` | Bypasses colour — use `log_success` |
| `echo "  ⚠ ..."` | Bypasses colour — use `log_warn` |
| `echo "  → ..."` | Bypasses colour — use `log_step` |
| `printf "  ---..."` | Table separator row — use blank line instead |
| Raw `read -p "[y/N]"` | Use `prompt_yes_no` |

---

## Reference: Cloudflare Wizard Screen (canonical example)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Cloudflare Tunnel Setup (API Method)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ℹ Tunnel name: weekendstack-tunnel
  ℹ Using Cloudflare API token
  → Validating API token...
  ✓ API token is valid

```
