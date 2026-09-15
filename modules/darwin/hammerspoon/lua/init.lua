local whu = require("window-hotkey-utils")
local browsers = require("browsers")
local picker = require("picker")

-- ─── Per-app US keyboard layout forcing ────────────────────────────
-- A window filter rather than an app watcher: windowFocused also fires for the
-- programmatic focus changes the hotkey toggles make.

local forceUSApps = {
  ["Ghostty"] = true,
  ["Neovide"] = true,
  ["iTerm2"] = true,
  ["Cursor"] = true,
  ["Obsidian"] = true,
}

-- Last non-US layout before forcing kicked in. Never set to US so
-- restore always has a valid target (or nil if the user was already in US).
local previousSourceID = nil

local function activateUSLayout()
  local current = hs.keycodes.currentSourceID()
  if current ~= whu.us then
    previousSourceID = current
  end
  whu.setInputSource(whu.us)
end

local function restorePreviousLayout()
  if previousSourceID then
    whu.setInputSource(previousSourceID)
    previousSourceID = nil
  end
end

-- new(nil), not new(true): the default filter's visible=true rule keeps
-- Spotlight and Notification Center from restoring the layout mid-session.
-- Both constructors have a failure mode — see the README and SYSMI-63.
local focusFilter = hs.window.filter.new(nil)

focusFilter:subscribe(hs.window.filter.windowFocused, function(win)
  local app = win:application()
  if not app then
    return
  end

  -- Read here rather than set by the hotkey, so the handler sees the layout the
  -- user was actually in and can record it for the way back.
  local wanted = whu.claimInputSource(app)

  if forceUSApps[app:name()] or wanted == whu.us then
    activateUSLayout()
  elseif wanted then
    -- Leaving the forced state by a hotkey that names its own layout: there is
    -- nothing to return to afterwards.
    previousSourceID = nil
    whu.setInputSource(wanted)
  else
    restorePreviousLayout()
  end
end)

-- windowFocused alone misses a window that disappears without another taking
-- focus.
local forceUSFilter = hs.window.filter.new(false)
for name in pairs(forceUSApps) do
  forceUSFilter:setAppFilter(name, {})
end

forceUSFilter:subscribe(hs.window.filter.windowNotVisible, function()
  local focused = hs.window.focusedWindow()
  if focused then
    local app = focused:application()
    if app and forceUSApps[app:name()] then
      return
    end
  end
  restorePreviousLayout()
end)

-- ─── Custom layouts ────────────────────────────────────────────────

local function chatLayout(screen)
  local builtIn = whu.builtInScreen()
  if builtIn then
    return whu.fullFrame(builtIn)
  end
  if whu.isWidescreen(screen) then
    return whu.rightFrame(screen, 0.35, 3)
  end
  return whu.rightFrame(screen, 0.5, 3)
end

-- ─── App hotkeys ───────────────────────────────────────────────────

-- Ghostty (hyper+s) — US layout via forceUSApps, auto-position new windows
whu.bindToggle("s", "com.mitchellh.ghostty", whu.sidebar("left", 0.6), {
  inputSource = whu.us,
  watchCreate = true,
})

-- Slack (hyper+k)
whu.bindToggle("k", "com.tinyspeck.slackmacgap", chatLayout)

-- Teams (hyper+i)
whu.bindToggle("i", "com.microsoft.teams2", chatLayout)

-- Finder (hyper+f)
whu.bindToggle("f", "com.apple.finder", whu.corner("topleft", 800, 600, 10))

-- Calendar (hyper+x) — no resize, just center on active screen.
-- Not c: that key belongs to a browser profile.
whu.bindToggle("x", "com.apple.iCal", whu.center())

-- Obsidian (hyper+j) — US layout via forceUSApps
whu.bindToggle("j", "md.obsidian", whu.sidebar("right", 0.4), {
  inputSource = whu.us,
})

-- Spotify (hyper+m)
whu.bindToggle("m", "com.spotify.client", whu.corner("topleft", 1064, 800, 10))

-- Discord (hyper+d) — chat layout like Slack/Teams
whu.bindToggle("d", "com.hnc.Discord", chatLayout)

-- Windows App / RDP (hyper+z) — toggle/focus only, never resize
whu.bindToggle("z", "com.microsoft.rdc.macos", nil)

-- ─── Browser profiles ──────────────────────────────────────────────
-- Keys, labels and profiles all come from local.browsers.targets, so the
-- hotkeys and the picker rows cannot disagree about what exists.
--
-- These bind AFTER the app hotkeys above: hs.hotkey lets a later bind win, so
-- a key claimed by both would silently resolve to the browser. The nix option
-- asserts the targets do not collide with each other; it cannot see this file,
-- so keeping the two sets disjoint is a matter of reading them together.

local browserLayout = whu.sidebar("right", 0.4)

for _, target in ipairs(browsers.targets) do
  hs.hotkey.bind(whu.hyper, target.key, function()
    browsers.toggle(target, browserLayout)
  end)
end

picker.setup()
