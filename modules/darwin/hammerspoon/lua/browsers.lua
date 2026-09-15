-- Browser targets: display names, launching, and finding existing windows.
--
-- Nothing here may hard-code a profile name. This repo is public, so display
-- names are read from the browser's own Local State at runtime.

local M = {}

local whu = require("window-hotkey-utils")

local home = os.getenv("HOME") or ""

-- Where each Chromium browser keeps the directory -> display name mapping.
-- Browser knowledge, not client knowledge, so it stays in Lua rather than
-- inflating the nix option.
M.localState = {
  ["com.google.Chrome"] = home .. "/Library/Application Support/Google/Chrome/Local State",
  ["com.brave.Browser"] = home .. "/Library/Application Support/BraveSoftware/Brave-Browser/Local State",
  ["com.microsoft.edgemac"] = home .. "/Library/Application Support/Microsoft Edge/Local State",
  ["com.vivaldi.Vivaldi"] = home .. "/Library/Application Support/Vivaldi/Local State",
}

local ok, generated = pcall(require, "generated.targets")
M.targets = (ok and type(generated) == "table") and generated or {}

-- Loudly, because the degraded state is silent: with no targets three hotkeys
-- simply stop responding. Reachable whenever the tree reloads before
-- build-switch has generated the file.
if #M.targets == 0 then
  print("hammerspoon: no browser targets — generated/targets.lua is missing or empty; b/v/c will not bind")
end

-- ─── Profile display names ────────────────────────────────────────

-- Chromium rewrites Local State atomically, so no locking is needed. The
-- previous value is kept so a failed read degrades to a stale name, not none.
local cache = {}

local function readProfiles(path)
  local attr = hs.fs.attributes(path)
  local previous = cache[path] and cache[path].profiles
  if not attr or attr.mode ~= "file" then
    return previous
  end

  local key = tostring(attr.modification) .. "." .. tostring(attr.size)
  if cache[path] and cache[path].key == key then
    return cache[path].profiles
  end

  -- hs.json.read returns nil for every unreadable file; it only throws when
  -- handed a non-string, which cannot happen here.
  local decoded = hs.json.read(path)
  local info = type(decoded) == "table" and type(decoded.profile) == "table" and decoded.profile.info_cache
  if type(info) ~= "table" then
    return previous
  end

  local profiles = {}
  for dir, entry in pairs(info) do
    if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
      profiles[dir] = { name = entry.name, gaia = entry.gaia_given_name }
    end
  end

  cache[path] = { key = key, profiles = profiles }
  return profiles
end

--- All known profiles for a bundle, how many there are, and whether the list
--- could be read at all.
---
--- Chromium only labels window titles when it knows more than one profile,
--- hence the count. Readability is separate because a count of zero otherwise
--- looks like a count of one, and every window would match every target.
function M.profiles(bundle)
  local path = M.localState[bundle]
  if not path then
    return {}, 0, false
  end
  local profiles = readProfiles(path)
  if not profiles then
    return {}, 0, false
  end
  local count = 0
  for _ in pairs(profiles) do
    count = count + 1
  end
  return profiles, count, true
end

--- Display name for a target's profile, and whether it was actually found.
function M.displayName(target)
  if not target.profileDir then
    return nil, false
  end
  local profiles = M.profiles(target.bundle)
  local entry = profiles[target.profileDir]
  if entry then
    return entry.name, true
  end
  return target.profileDir, false
end

--- Picker row text: the generic label, plus the real profile name when it can
--- be read. The label alone is what the repo knows; the name is runtime-only.
function M.label(target)
  local name, found = M.displayName(target)
  if not found or name == target.label then
    return target.label
  end
  return target.label .. " — " .. name
end

-- ─── Matching a window to a profile ───────────────────────────────

-- The accessible title, which is what hs.window reads, ends with
-- GetAvatarNameForProfile() — for a signed-in profile "<GAIA given name>
-- (<Local State name>)". Matching the bare Local State name finds nothing.
local function tailForms(entry)
  local forms = {}
  if entry and type(entry.name) == "string" and entry.name ~= "" then
    if type(entry.gaia) == "string" and entry.gaia ~= "" then
      forms[#forms + 1] = entry.gaia .. " (" .. entry.name .. ")"
      -- A signed-in profile still carrying Chrome's default local name shows
      -- the GAIA name alone.
      forms[#forms + 1] = entry.gaia
    end
    forms[#forms + 1] = entry.name
  end
  return forms
end

local function endsWithTail(title, tail)
  if #title <= #tail or title:sub(-#tail) ~= tail then
    return false
  end
  -- A page title can end in the same words by chance, so require a
  -- non-alphanumeric boundary. The separator itself is localized.
  return title:sub(-#tail - 1, -#tail - 1):match("%w") == nil
end

--- Which profile directory a title belongs to, or nil when none matches.
---
--- Longest match across all profiles, because one display name can be a suffix
--- of another — "Work" inside "Client Work" — and the shorter would otherwise
--- claim the longer profile's windows.
local function profileForTitle(profiles, title)
  -- Sorted, because pairs() order is undefined and this decides which browser
  -- a link is shown in: the same title must resolve to the same profile on
  -- every reload, and a tie must break the same way every time.
  local dirs = {}
  for dir in pairs(profiles) do
    dirs[#dirs + 1] = dir
  end
  table.sort(dirs)

  local bestDir, bestLen = nil, 0
  for _, dir in ipairs(dirs) do
    for _, tail in ipairs(tailForms(profiles[dir])) do
      if #tail > bestLen and endsWithTail(title, tail) then
        bestDir, bestLen = dir, #tail
      end
    end
  end
  return bestDir
end

--- Every window belonging to a target's profile.
---
--- Uses applicationsForBundleID, not application.get: an automation copy of
--- Chrome driven with its own --user-data-dir reports the same bundle id, and
--- get() returns only one of them.
local warned = {}

local function belongs(target, win, profiles, count, known)
  -- Chromium's companion status-bar windows have no id and are never
  -- minimized, so an unfiltered list makes the hotkey dead whenever the real
  -- window is.
  if not win:isStandard() then
    return false
  end
  if not target.profileDir or not known or count <= 1 then
    -- Nothing to distinguish: no profile asked for, no profile list readable,
    -- or the browser knows only one and so labels nothing.
    return true
  end
  return profileForTitle(profiles, win:title() or "") == target.profileDir
end

function M.windowsFor(target)
  local profiles, count, known = M.profiles(target.bundle)
  local matched = {}

  -- Without a Local State path nothing distinguishes this bundle's windows, so
  -- two targets sharing it would quietly fight over one.
  if target.profileDir and not known and not warned[target.bundle] then
    warned[target.bundle] = true
    print("hammerspoon: no Local State path for " .. target.bundle .. "; profiles cannot be told apart")
  end

  for _, app in ipairs(hs.application.applicationsForBundleID(target.bundle) or {}) do
    for _, win in ipairs(app:allWindows()) do
      if belongs(target, win, profiles, count, known) then
        matched[#matched + 1] = win
      end
    end
  end

  return matched
end

--- Whether a window found some other way — the focused one — is this target's.
function M.owns(target, win)
  local app = win and win:application()
  if not app or app:bundleID() ~= target.bundle then
    return false
  end
  return belongs(target, win, M.profiles(target.bundle))
end

-- ─── Launching ────────────────────────────────────────────────────

--- Open a URL, or the profile itself when url is nil.
function M.launch(target, url)
  local args = {}

  -- --args applies only to a new instance, which is what -n requests. Without
  -- it the profile switch and the URL are both dropped. It belongs nowhere
  -- else: on a plain launch it forces a real second copy of the browser.
  if target.profileDir then
    args[#args + 1] = "-n"
  end

  local path = hs.application.pathForBundleID(target.bundle)
  if path then
    args[#args + 1] = "-a"
    args[#args + 1] = path
  else
    args[#args + 1] = "-b"
    args[#args + 1] = target.bundle
  end

  if target.profileDir then
    args[#args + 1] = "--args"
    args[#args + 1] = "--profile-directory=" .. target.profileDir
    if url then
      args[#args + 1] = url
    end
  elseif url then
    -- Not behind --args: open(1) hands those to the app as argv without
    -- opening them, and only Chromium reads a URL back out of its own.
    args[#args + 1] = url
  end

  -- Absolute path: hs.task constructs happily from a bare command name but
  -- its :start() then returns false and nothing runs.
  local task = hs.task.new("/usr/bin/open", nil, args)
  return task ~= nil and task:start()
end

-- ─── Toggling ─────────────────────────────────────────────────────

-- One spec per target, built once, so its pending launch timer is keyed the
-- same on every press.
local specs = {}

--- Focus this profile's window, or put it away if it already has focus.
function M.toggle(target, layoutFn)
  local spec = specs[target.key]
  if not spec or spec.target ~= target or spec.layout ~= layoutFn then
    spec = {
      target = target,
      id = "browser:" .. target.key,
      bundle = target.bundle,
      windows = function()
        return M.windowsFor(target)
      end,
      owns = function(win)
        return M.owns(target, win)
      end,
      launch = function()
        M.launch(target, nil)
      end,
      layout = layoutFn,
      -- Browsers are typed in, not just clicked, so the layout goes back.
      inputSource = whu.fiProg,
    }
    specs[target.key] = spec
  end
  whu.toggle(spec)
end

return M
