-- Window management utilities for hotkey-driven app toggling and layout.

local M = {}

M.hyper = { "cmd", "ctrl", "alt", "shift" }
M.us = "com.apple.keylayout.US"
M.fiProg = "org.sil.ukelele.keyboardlayout.finnishprogrammerkeyboard.finnish-prog"

-- ─── Input source ─────────────────────────────────────────────────

-- The retry for the latest set. Held, because hs.timer keeps no registry and an
-- unreferenced one can be collected before it fires; replaced, because an older
-- one left armed would re-assert a layout a later set superseded.
M._inputRetry = nil

-- Retried once: macOS drops the first set (Hammerspoon #1429).
function M.setInputSource(sourceID)
  if M._inputRetry then
    M._inputRetry:stop()
  end
  hs.keycodes.currentSourceID(sourceID)
  local timer
  timer = hs.timer.doAfter(0.05, function()
    if M._inputRetry == timer then
      M._inputRetry = nil
    end
    if hs.keycodes.currentSourceID() ~= sourceID then
      hs.keycodes.currentSourceID(sourceID)
    end
  end)
  M._inputRetry = timer
end

-- A hotkey's layout is applied when its window takes focus, not when the key is
-- pressed. Set at press time it lands under the app still being typed in, and
-- ahead of the windowFocused handler, which then reads the new layout as the one
-- to restore later and strands the machine in it.
--
-- One slot: only the latest press expresses what the user wants. It expires so
-- a window that never took focus cannot set a layout on some unrelated later
-- click into the same app.
M.intentTTL = 10
local intent = nil

-- What init.lua does when a window takes focus. The windowFocused filter calls
-- it, and so does the check below; it must be safe to run twice for one focus.
M.onFocus = nil

-- Measured on this machine, 2026-09-16, against a windowFocused subscriber:
-- the event fires for a scripted win:focus() on another app, for unhide+focus
-- (the window reads visible immediately, so the default filter's visible rule
-- does not drop it), for unminimize+focus from another app, for a launch, for
-- reopening an app with no windows (frontmost or not), for focusing another
-- window of the frontmost app, and on arriving at a Space through gotoSpace.
--
-- One case emits nothing: the app is already frontmost and the window raised is
-- already its focused window, so nothing changes. The toggle answers that with
-- the branch below rather than a timer, since an app that already has focus is
-- the app being typed in — there is nothing for an immediate switch to disturb.
function M.requestInputSource(bundleID, sourceID)
  intent = { bundle = bundleID, source = sourceID, at = hs.timer.secondsSinceEpoch() }
end

--- The layout a hotkey asked for, if this focus is the one it was waiting for.
--- Consumed either way once the app matches.
---
--- Matched on the app, not the window: an activation event carries whatever the
--- app's focused window was at the time, which after an unminimize is not yet
--- the window the hotkey raised (measured).
function M.claimInputSource(app)
  local pending = intent
  if not pending or not app or app:bundleID() ~= pending.bundle then
    return nil
  end
  intent = nil
  if hs.timer.secondsSinceEpoch() - pending.at > M.intentTTL then
    return nil
  end
  return pending.source
end

-- ─── Screen helpers ───────────────────────────────────────────────

function M.activeScreen()
  return hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
end

function M.isWidescreen(screen)
  local f = screen:frame()
  return f.w / f.h > 2.2
end

function M.builtInScreen()
  for _, s in ipairs(hs.screen.allScreens()) do
    if (s:name() or ""):find("Built%-in") then
      return s
    end
  end
  return nil
end

-- ─── Frame builders (for custom layout functions) ─────────────────

function M.fullFrame(screen)
  return screen:frame()
end

function M.leftFrame(screen, fraction, margin)
  margin = margin or 0
  local f = screen:frame()
  return hs.geometry.rect(f.x + margin, f.y + margin, math.floor(f.w * fraction) - margin, f.h - 2 * margin)
end

function M.rightFrame(screen, fraction, margin)
  margin = margin or 0
  local f = screen:frame()
  local w = math.floor(f.w * fraction)
  return hs.geometry.rect(f.x + f.w - w, f.y + margin, w - margin, f.h - 2 * margin)
end

function M.centerFrame(screen, win)
  local f = screen:frame()
  local wf = win:frame()
  return hs.geometry.rect(f.x + (f.w - wf.w) / 2, f.y + (f.h - wf.h) / 2, wf.w, wf.h)
end

-- ─── Layout factories ─────────────────────────────────────────────
-- Each returns function(screen, win) → hs.geometry.rect, compatible
-- with bindToggle's layoutFn signature.

--- Sidebar: fraction of screen width on one side.
--- On widescreen the window occupies `fraction` of the width on `side`,
--- with `margin` on the outer edges (inner split edge has no margin so
--- adjacent sidebars tile flush).
--- On non-widescreen the window fills the screen with margin on all sides.
function M.sidebar(side, fraction, margin)
  margin = margin or 3
  return function(screen)
    if not M.isWidescreen(screen) then
      local f = screen:frame()
      return hs.geometry.rect(f.x + margin, f.y + margin, f.w - 2 * margin, f.h - 2 * margin)
    end
    if side == "right" then
      return M.rightFrame(screen, fraction, margin)
    end
    return M.leftFrame(screen, fraction, margin)
  end
end

--- Center: preserve current window size, center on active screen.
function M.center()
  return function(screen, win)
    return M.centerFrame(screen, win)
  end
end

--- Corner: fixed pixel dimensions anchored to a screen corner.
function M.corner(position, width, height, margin)
  margin = margin or 10
  return function(screen)
    local f = screen:frame()
    local x, y
    if position == "topleft" or position == "bottomleft" then
      x = f.x + margin
    else
      x = f.x + f.w - width - margin
    end
    if position == "topleft" or position == "topright" then
      y = f.y + margin
    else
      y = f.y + f.h - height - margin
    end
    return hs.geometry.rect(x, y, width, height)
  end
end

-- ─── Window helpers ───────────────────────────────────────────────

--- Position a window with a layout function, if there is anything to do.
---
--- A nil layoutFn means "never reposition", which is how toggle-only bindings
--- are expressed.
function M.applyLayout(win, layoutFn)
  if not win or not layoutFn then
    return false
  end
  win:setFrame(layoutFn(M.activeScreen(), win))
  return true
end

--- Is `win` one of `windows`?
---
--- hs.window:id() is 0 for a window whose AX id cannot be read — Hammerspoon
--- 1.1.1 pushes the integer unconditionally — and Chromium keeps several such
--- helper windows per real one. Comparing two of them would report an unrelated
--- window as a match, so a window with no readable id is never one.
function M.containsWindow(windows, win)
  local id = win and win:id()
  if not id or id == 0 then
    return false
  end
  for _, w in ipairs(windows) do
    if w:id() == id then
      return true
    end
  end
  return false
end

-- ─── Toggling ─────────────────────────────────────────────────────
-- One toggle for every hotkey. What differs between an app and a browser
-- profile is which windows count as its and how a new one is opened, so those
-- are passed in; everything else — putting away, raising, positioning a launch,
-- the layout — is the same code.
--
-- spec.id           — distinct per hotkey; keys the held launch timer
-- spec.bundle       — the bundle whose windows these are
-- spec.windows()    — the windows this hotkey owns, preferred first
-- spec.owns(win)    — whether a window seen some other way is one of them
-- spec.launch()     — open one when there are none
-- spec.layout       — layoutFn(screen, win) → rect, or nil to never reposition
-- spec.inputSource  — source ID to switch to on raise, or false
-- spec.placesNew    — true when something else already positions new windows
-- spec.byAppAlone() — optional; false when the app's process does not identify
--                     these windows by itself, as for one browser profile of several
-- spec.hidesWhenFrontmost — true when a press should put the app away whenever
--                     it holds focus, even with no window of its own focused

-- Timers for windows that do not exist yet. Held, because hs.timer keeps no
-- registry and would collect them; keyed by spec.id so a press replaces rather
-- than stacks.
M._pending = {}

local function cancelPending(id)
  local previous = M._pending[id]
  if previous then
    previous:stop()
    M._pending[id] = nil
  end
end

--- The spec's windows, plus the focused window when the enumeration missed it.
---
--- A full-screen window drops out of app:allWindows() while focusedWindow()
--- still returns it, so without this a press from inside a full-screen app sees
--- nothing of its own and launches a duplicate instead of putting it away.
local function windowsWithFocused(spec, focused)
  local windows = spec.windows()
  if focused and not M.containsWindow(windows, focused) and spec.owns(focused) then
    table.insert(windows, 1, focused)
  end
  return windows
end

--- Put a focused window of the spec's away.
---
--- Hiding takes every window of the app with it, so it is used only when
--- nothing else of that app is showing; otherwise just this window minimizes.
--- A full-screen window cannot minimize, so it always hides.
local function putAway(windows, focused)
  local app = focused:application()
  if not app then
    focused:minimize()
    return
  end
  local othersVisible = false
  if not focused:isFullScreen() then
    for _, w in ipairs(app:visibleWindows()) do
      -- Standard only: Chromium's companion windows have no readable id, so they
      -- never match and would otherwise always count as someone else's.
      if w:isStandard() and not M.containsWindow(windows, w) then
        othersVisible = true
        break
      end
    end
  end
  if othersVisible then
    focused:minimize()
  else
    app:hide()
  end
end

-- ─── Full-screen windows on another Space ─────────────────────────
-- From any other Space a full-screen window is absent from app:allWindows(),
-- and hs.window.get() refuses its id. hs.spaces still lists the id, but not who
-- owns it, and hs.window.list() reports on-screen windows only. The window
-- server's full list does carry the owner, so it is read through JXA — about
-- 70ms, and only once a full-screen Space exists and the hotkey found nothing.

-- Only document windows: layer 0, not transparent, and real-sized. A Space's
-- window list also carries tooltips, overlays and ordered-out leftovers, and an
-- app owning one of those on a full-screen Space does not have a window there.
M.ownersScript = [[
ObjC.import("CoreGraphics");
var all = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, 0)));
all.filter(function (w) {
  var b = w.kCGWindowBounds || {};
  return w.kCGWindowLayer === 0 && w.kCGWindowAlpha > 0 && b.Width >= 200 && b.Height >= 200;
}).map(function (w) { return w.kCGWindowNumber + " " + w.kCGWindowOwnerPID; }).join("\n");
]]

--- Window id → owning pid, for every document window the window server knows.
function M.windowOwners()
  -- hs.execute goes through sh, so the script is single-quoted and must not
  -- contain a single quote itself.
  local out, ok = hs.execute("/usr/bin/osascript -l JavaScript -e '" .. M.ownersScript .. "'")
  local owners = {}
  if not ok or type(out) ~= "string" then
    return owners
  end
  for id, pid in out:gmatch("(%d+) (%d+)") do
    owners[tonumber(id)] = tonumber(pid)
  end
  return owners
end

local function fullScreenSpaces()
  local ok, all = pcall(hs.spaces.allSpaces)
  if not ok or type(all) ~= "table" then
    return {}
  end
  -- Never the Space already on screen: going there does nothing, and a tiled
  -- split-view Space holds the other app's focus. launchOrFocus activates the app
  -- in place, as it always did.
  local activeOk, active = pcall(hs.spaces.activeSpaces)
  local onScreen = {}
  for _, id in pairs(activeOk and type(active) == "table" and active or {}) do
    onScreen[id] = true
  end
  local spaces = {}
  for _, ids in pairs(all) do
    for _, id in ipairs(ids) do
      if not onScreen[id] and hs.spaces.spaceType(id) == "fullscreen" then
        spaces[#spaces + 1] = id
      end
    end
  end
  -- pairs() order is undefined; the same press must pick the same Space.
  table.sort(spaces)
  return spaces
end

--- A raise for the spec's full-screen window on another Space, or nil.
---
--- Owned by pid, so only a spec whose app alone identifies its windows can use
--- it: a browser profile sharing a process with another cannot tell which of
--- them a full-screen window is, and going to the wrong one is worse than a new
--- window.
-- When the last press went to a Space. gotoSpace drives Mission Control and
-- blocks while it does; a second one mid-transition can leave Mission Control
-- open, so presses inside this window do nothing rather than start another.
M.spaceSettle = 1.5
M._wentToSpaceAt = nil

function M.fullScreenWindow(spec)
  if spec.byAppAlone and not spec.byAppAlone() then
    return nil
  end
  local now = hs.timer.secondsSinceEpoch()
  if M._wentToSpaceAt and now - M._wentToSpaceAt < M.spaceSettle then
    return function() end
  end
  local pids = {}
  local any = false
  local apps = hs.application.applicationsForBundleID(spec.bundle) or {}
  for _, app in ipairs(apps) do
    local pid = app:pid()
    if pid then
      pids[pid] = true
      any = true
    end
  end
  if not any then
    return nil
  end

  local spaces = fullScreenSpaces()
  if #spaces == 0 then
    return nil
  end

  local owners = M.windowOwners()
  for _, space in ipairs(spaces) do
    local ok, ids = pcall(hs.spaces.windowsForSpace, space)
    for _, id in ipairs(ok and ids or {}) do
      if pids[owners[id]] then
        return function()
          -- A press from inside a full-screen app hides it, and a hidden app's
          -- Space shows nothing, so it comes back first.
          for _, app in ipairs(apps) do
            app:unhide()
          end
          -- Goes through Mission Control, which is unavoidable and brief. On
          -- arrival the window takes focus, so the layout request still applies.
          M._wentToSpaceAt = now
          -- It returns nil and a message rather than raising when it cannot go.
          local called, arrived = pcall(hs.spaces.gotoSpace, space)
          if not called or not arrived then
            M._wentToSpaceAt = nil
            spec.launch()
          end
        end
      end
    end
  end
  return nil
end

function M.toggle(spec)
  -- Every press supersedes a pending launch. Left armed, it would reposition
  -- whichever window the provider lists first when it fires — not necessarily
  -- the one this press raised.
  cancelPending(spec.id)

  local focused = hs.window.focusedWindow()
  local windows = windowsWithFocused(spec, focused)
  -- Read before anything is raised: an app that already holds focus gets its
  -- layout switched at once, because no activation event will follow and the
  -- app being typed in is the one asked for.
  local front = hs.application.frontmostApplication()
  local hadFocus = front ~= nil and front:bundleID() == spec.bundle

  if #windows == 0 then
    local elsewhere = M.fullScreenWindow(spec)
    if elsewhere then
      elsewhere()
    else
      spec.launch()
    end
    if spec.inputSource then
      M.requestInputSource(spec.bundle, spec.inputSource)
    end
    if elsewhere or not spec.layout or spec.placesNew then
      return
    end
    local timer
    timer = hs.timer.doAfter(1.5, function()
      if M._pending[spec.id] == timer then
        M._pending[spec.id] = nil
      end
      M.applyLayout(spec.windows()[1], spec.layout)
    end)
    M._pending[spec.id] = timer
    return
  end

  if M.containsWindow(windows, focused) then
    putAway(windows, focused)
    return
  end

  -- The app has focus but not through one of these windows — a dialog, a panel,
  -- Finder's desktop. The press still means "put it away".
  if hadFocus and spec.hidesWhenFrontmost then
    front:hide()
    return
  end

  local win = windows[1]
  if not win:isVisible() then
    for _, w in ipairs(windows) do
      if w:isVisible() then
        win = w
        break
      end
    end
  end

  local app = win:application()
  if app then
    app:unhide()
  end
  -- allWindows() counts minimized windows, and win:focus() does not
  -- deminiaturize, so without this the press focuses what the window server
  -- will not raise.
  if win:isMinimized() then
    win:unminimize()
  end
  M.applyLayout(win, spec.layout)
  win:focus()

  if spec.inputSource then
    M.requestInputSource(spec.bundle, spec.inputSource)
    if hadFocus and M.onFocus then
      M.onFocus(win)
    end
  end
end

-- ─── Hotkey binding ───────────────────────────────────────────────
-- Bind a hyper+key hotkey that toggles an app and positions its window.
--
-- layoutFn(screen, win) → hs.geometry.rect
--   Pass nil to toggle/focus without ever repositioning the window.
--
-- opts.inputSource  — source ID to switch to on raise (default: M.fiProg), or false
-- opts.watchCreate  — auto-position every new window (for terminal apps)

M._filters = {}

local function ownedByBundle(bundleID)
  return function(win)
    local app = win and win:application()
    return app ~= nil and app:bundleID() == bundleID and win:isStandard()
  end
end

--- The app's running instance, if any. Not hs.application.get: for an app that
--- is not running it falls back to matching names and then every window title
--- as a pattern, which is slow and can hand back a window instead of an app.
local function runningApp(bundleID)
  return (hs.application.applicationsForBundleID(bundleID) or {})[1]
end

--- Every standard window of the app, its main window first.
local function appWindows(bundleID, owns)
  local app = runningApp(bundleID)
  if not app then
    return {}
  end
  local out = {}
  local main = app:mainWindow()
  if main and owns(main) then
    out[1] = main
  end
  for _, w in ipairs(app:allWindows()) do
    if owns(w) and not M.containsWindow(out, w) then
      out[#out + 1] = w
    end
  end
  return out
end

function M.bindToggle(key, bundleID, layoutFn, opts)
  opts = opts or {}
  -- Explicit nil test: the `and`/`or` idiom cannot carry a falsey value, so
  -- `inputSource = false` would collapse to the default.
  local inputSource = M.fiProg
  if opts.inputSource ~= nil then
    inputSource = opts.inputSource
  end

  local owns = ownedByBundle(bundleID)

  -- Matched by bundle id, never by name: nameForBundleID is not app:name()
  -- (Brave vs Brave Browser, Chrome vs Google Chrome), and a filter built from
  -- the wrong one matches nothing without saying so.
  if opts.watchCreate then
    local wf = hs.window.filter.new(owns)
    wf:subscribe(hs.window.filter.windowCreated, function(win)
      M.applyLayout(win, layoutFn)
      win:focus()
    end)
    M._filters[bundleID] = wf
  end

  local spec = {
    id = "app:" .. bundleID,
    bundle = bundleID,
    windows = function()
      return appWindows(bundleID, owns)
    end,
    owns = owns,
    launch = function()
      hs.application.launchOrFocusByBundleID(bundleID)
    end,
    layout = layoutFn,
    inputSource = inputSource,
    placesNew = opts.watchCreate == true,
    hidesWhenFrontmost = true,
  }

  hs.hotkey.bind(M.hyper, key, function()
    M.toggle(spec)
  end)
  return spec
end

return M
