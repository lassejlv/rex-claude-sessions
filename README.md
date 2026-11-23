# Recent Claude Sessions for Rex

A [Rex](https://www.superlogical.com/rex) plugin that lists your latest [Claude Code](https://claude.com/claude-code) sessions in the command palette and reopens the one you pick in a new tab, in its project folder, with `claude --resume`.

- Each row shows the session's title (your rename, Claude's title, or your last prompt), its folder, and how long ago it was used.
- Sessions that ran with `--dangerously-skip-permissions` are marked **bypass** and resume with it again.
- Several Claude accounts, each with its own `CLAUDE_CONFIG_DIR`, can share one list.
- When Claude exits, the tab becomes a shell in the project.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/lassejlv/rex-claude-sessions/main/install.sh | sh
```

Run it on the machine that runs your Rex server. It copies the plugin to `~/.config/rex/plugins/claude-sessions/init.lua`, adds a block that loads it to `~/.config/rex/init.lua`, and reloads Rex. Run it again to update; it keeps the block and your options.

Then press <kbd>Shift</kbd>+<kbd>Cmd</kbd>+<kbd>R</kbd>, or search for "Recent Claude Sessions" in the command palette.

Needs a Rex version with `rex.ui.pick` (control API revision 17 or later) and `claude` on the login shell's `PATH`.

## Configuration

Pass options to `setup` in the block the installer added to `init.lua`, then run `rex config reload`:

```lua
dofile(os.getenv("HOME") .. "/.config/rex/plugins/claude-sessions/init.lua").setup({
  accounts = {
    { name = "claude" },                      -- ~/.claude
    { name = "work", dir = "~/.claude-work" }, -- resumed with CLAUDE_CONFIG_DIR=~/.claude-work
  },
  limit = 60,           -- sessions to list
  key = "shift+cmd+r",  -- false for no shortcut
})
```

| Option | Default | Description |
| --- | --- | --- |
| `accounts` | `{ { name = "claude" } }` | The Claude config folders to read. `name` is shown in the list. An account with `dir` is resumed with `CLAUDE_CONFIG_DIR` set to it; one without uses `~/.claude`. |
| `limit` | `60` | How many sessions to list, newest first. |
| `key` | `"shift+cmd+r"` | The shortcut, or `false` for none. |

If you use shell aliases such as `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'`, add one account per alias with the same folder.

## Command line

```sh
rex do claude_resume session=claude:<session-id>
rex do claude_resume session=work:<session-id> bypass=false
```

`session` is `<account>:<session id>`, or just the session id. `bypass` overrides the detected permission mode.

## How bypass is detected

Claude Code writes a `permission-mode` record to each session's transcript. A session counts as bypass if it started in `bypassPermissions` mode or was last switched to it. The start counts on its own because resuming a session without the flag records a different mode.

## Uninstall

Delete the `-- >>> claude-sessions >>>` block from `~/.config/rex/init.lua` and the `~/.config/rex/plugins/claude-sessions` folder, then run `rex config reload`.

## License

MIT
