-- claude-sessions for Rex: "Recent Claude Sessions…" in the command palette
-- lists your latest Claude Code sessions and reopens the one you pick in a new
-- tab, in its project folder, running `claude --resume`.
-- https://github.com/lassejlv/rex-claude-sessions
--
-- Load it from ~/.config/rex/init.lua:
--
--   dofile(os.getenv("HOME") .. "/.config/rex/plugins/claude-sessions/init.lua").setup({
--     accounts = {                               -- optional
--       { name = "claude" },                     -- the default ~/.claude
--       { name = "work", dir = "~/.claude-work" }, -- run with CLAUDE_CONFIG_DIR
--     },
--     limit = 60,                                -- optional, sessions to list
--     key = "shift+cmd+r",                       -- optional, false for no key
--   })
--
-- Sessions that ran with --dangerously-skip-permissions are marked "bypass" and
-- resume with it again.
--
-- From the CLI: rex do claude_resume session=claude:<session-id> [bypass=false]

local M = {}

local SHELL = "com.superlogical.terminal.shell"
local HOME = os.getenv("HOME") or ""
local CHUNK = 65536

local DEFAULT_ACCOUNTS = { { name = "claude" } }

local function expand(path) return (path:gsub("^~", HOME)) end

local function tilde(path)
  if path == HOME then return "~" end
  if path:sub(1, #HOME + 1) == HOME .. "/" then return "~" .. path:sub(#HOME + 1) end
  return path
end

local function exists(path)
  local ok = rex.exec({ "test", "-d", path }, { timeout = 2 })
  return ok ~= nil and ok.ok
end

local function ago(seconds)
  if seconds < 60 then return "now" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
  if seconds < 86400 * 30 then return math.floor(seconds / 86400) .. "d" end
  return os.date("%b %d", os.time() - seconds)
end

-- The start and end of a transcript, which hold the titles, the first cwd, and
-- the newest rename, without reading files that can run to many megabytes.
local function read_ends(path)
  local f = io.open(path, "rb")
  if f == nil then return nil end
  local size = f:seek("end")
  f:seek("set", 0)
  local head = f:read(CHUNK) or ""
  local tail = ""
  if size > CHUNK then
    f:seek("set", math.max(CHUNK, size - CHUNK))
    tail = (f:read(CHUNK) or ""):gsub("^[^\n]*\n", "")
  end
  f:close()
  return head .. "\n" .. tail
end

local function field(line, key)
  local decoded = rex.json.decode(line)
  return type(decoded) == "table" and decoded[key] or nil
end

-- Claude names a project's folder after its path, every other character a dash.
local function project_dir(path) return path:match("([^/]+)/[^/]+$") end
local function encode(cwd) return (cwd:gsub("[^%w]", "-")) end

local function describe(path)
  local text = read_ends(path)
  if text == nil then return nil end
  local project = project_dir(path)
  local info = {}
  for line in text:gmatch("[^\n]+") do
    if line:find('"type":"custom-title"', 1, true) then
      info.custom = field(line, "customTitle") or info.custom
    elseif line:find('"type":"ai-title"', 1, true) then
      info.ai = field(line, "aiTitle") or info.ai
    elseif line:find('"type":"last-prompt"', 1, true) then
      info.prompt = field(line, "lastPrompt") or info.prompt
    elseif line:find('"type":"permission-mode"', 1, true) then
      local mode = line:match('"permissionMode":"(%a+)"')
      info.first_mode = info.first_mode or mode
      info.last_mode = mode or info.last_mode
    elseif info.cwd == nil and line:find('"cwd":"', 1, true) then
      -- Only the transcript's own cwd field, not one quoted inside tool output.
      local cwd = field(line, "cwd")
      if type(cwd) == "string" then
        if encode(cwd) == project then info.cwd = cwd else info.fallback = info.fallback or cwd end
      end
    end
  end
  info.cwd = info.cwd or info.fallback
  if info.cwd == nil then return nil end
  local title = info.custom or info.ai or info.prompt or "Untitled session"
  title = title:gsub("%s+", " ")
  if #title > 80 then title = title:sub(1, 77) .. "…" end
  info.title = title
  -- Started with --dangerously-skip-permissions, or switched to it last. The start
  -- counts on its own because a resume without the flag records another mode.
  info.bypass = info.first_mode == "bypassPermissions" or info.last_mode == "bypassPermissions"
  return info
end

-- Each transcript's modification time and path, one per line. stat takes
-- different flags on macOS and BSD than on Linux.
local function list_transcripts(root)
  local find = { "find", root, "-mindepth", "2", "-maxdepth", "2", "-name", "*.jsonl", "-size", "+0",
    "-exec", "stat" }
  for _, format in ipairs({ { "-f", "%m %N" }, { "-c", "%Y %n" } }) do
    local argv = { unpack(find) }
    argv[#argv + 1], argv[#argv + 2] = format[1], format[2]
    argv[#argv + 1], argv[#argv + 2] = "{}", "+"
    local r = rex.exec(argv, { timeout = 10, stderr = false })
    if r ~= nil and r.ok then return r end
  end
  return nil
end

-- Every account's transcripts, newest first.
local function recent(accounts, limit)
  local files = {}
  for _, account in ipairs(accounts) do
    local r = list_transcripts(expand(account.dir or "~/.claude") .. "/projects")
    if r ~= nil then
      for line in r.stdout:gmatch("[^\n]+") do
        local mtime, path = line:match("^(%d+) (.+)$")
        if path ~= nil then
          files[#files + 1] = { account = account, mtime = tonumber(mtime), path = path,
            id = path:match("([^/]+)%.jsonl$") }
        end
      end
    end
  end
  table.sort(files, function(a, b) return a.mtime > b.mtime end)

  local sessions = {}
  for _, file in ipairs(files) do
    if #sessions >= limit then break end
    local info = describe(file.path)
    if info ~= nil then
      file.cwd, file.title, file.bypass = info.cwd, info.title, info.bypass
      sessions[#sessions + 1] = file
    end
  end
  return sessions
end

-- Runs Claude, with CLAUDE_CONFIG_DIR set for an account that has its own
-- folder, then leaves a shell so the tab stays in the project after Claude exits.
local LAUNCH = [[
id=$1 config=$2; shift 2
if [ -n "$config" ]; then CLAUDE_CONFIG_DIR="$config" claude --resume "$id" "$@"; else claude --resume "$id" "$@"; fi
exec "${SHELL:-/bin/sh}" -l
]]

local function resume(ctx, session, bypass)
  if not exists(session.cwd) then
    error("claude-sessions: " .. tilde(session.cwd) .. " isn't there anymore", 0)
  end
  local config = session.account.dir and expand(session.account.dir) or ""
  local w, err = rex.session.new_window{
    window_label = session.title,
    focus = true,
    layout = rex.layout.block{
      flavor = SHELL,
      label = session.account.name,
      options = {
        cwd = session.cwd,
        command = { "sh", "-c", LAUNCH, "claude-resume", session.id, config,
          bypass and "--dangerously-skip-permissions" or nil },
      },
    },
  }
  if w == nil then error("claude-sessions: couldn't open a tab: " .. tostring(err), 0) end
  -- The server makes the tab active, but the app keeps showing what it showed;
  -- ask it to go there. From the CLI there may be no app that accepts this.
  pcall(rex.client.queue, "session.select", { session_id = ctx.session_id, window_id = w.window_id })
  return { window_id = w.window_id, block_ids = w.block_ids, session_id = session.id,
    account = session.account.name, cwd = session.cwd, bypass = bypass }
end

function M.setup(opts)
  opts = opts or {}
  local accounts = opts.accounts or DEFAULT_ACCOUNTS
  local limit = opts.limit or 60

  rex.action{
    name = "claude_resume",
    title = "Recent Claude Sessions…",
    description = "Reopen a recent Claude Code session in a new tab, in its project folder.",
    category = "Claude",
    keywords = "claude code resume continue session project history",
    args = { session = "string?", bypass = "boolean?" },
    run = function(ctx, args)
      local sessions = recent(accounts, args.session and math.huge or limit)

      if args.session ~= nil then
        local account, id = args.session:match("^([^:]+):(.+)$")
        id = id or args.session
        for _, s in ipairs(sessions) do
          if s.id == id and (account == nil or s.account.name == account) then
            return resume(ctx, s, args.bypass == nil and s.bypass or args.bypass)
          end
        end
        error("claude-sessions: no session " .. args.session, 0)
      end

      if #sessions == 0 then error("claude-sessions: no Claude sessions found", 0) end
      local now = os.time()
      local items, by_id = {}, {}
      for _, s in ipairs(sessions) do
        local key = s.account.name .. ":" .. s.id
        by_id[key] = s
        items[#items + 1] = {
          id = key,
          title = s.title,
          subtitle = tilde(s.cwd),
          icon = "terminal",
          detail = s.account.name .. " · " .. ago(now - s.mtime) .. (s.bypass and " · bypass" or ""),
        }
      end
      local picked, why = rex.ui.pick{
        title = "Recent Claude sessions",
        placeholder = "Filter by title, folder, or account",
        confirm = "Resume",
        items = items,
      }
      if picked == nil then
        if why ~= "cancelled" then rex.log("warn", "claude-sessions: " .. tostring(why)) end
        return
      end
      return resume(ctx, by_id[picked], by_id[picked].bypass)
    end,
  }

  if opts.key ~= false then rex.bind(opts.key or "shift+cmd+r", "claude_resume") end
end

return M
