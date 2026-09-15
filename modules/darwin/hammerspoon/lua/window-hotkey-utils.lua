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

function M.requestInputSource(bundleID, sourceID)
  intent = { bundle = bundleID, source = sourceID, at = hs.timer.secondsSinceEpoch() }
end

--- The layout a hotkey asked for, if this focus is the one it was waiting for.
--- Consumed either way once the app matches.
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
--- hs.window:id() is nil for a window whose AX id cannot be read, and Chromium
--- keeps several such helper windows per real one. Comparing two nils would
--- report an unrelated window as a match, so a window with no id is never one.
function M.containsWindow(windows, win)
  local id = win and win:id()
  if not id then
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
      -- Standard only: Chromium's companion windows have no id, so they never
      -- match and would otherwise always count as someone else's.
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

function M.toggle(spec)
  -- Every press supersedes a pending launch. Left armed, it would reposition
  -- whichever window the provider lists first when it fires — not necessarily
  -- the one this press raised.
  cancelPending(spec.id)

  local focused = hs.window.focusedWindow()
  local windows = windowsWithFocused(spec, focused)

  if #windows == 0 then
    local elsewhere = M.fullScreenWindow and M.fullScreenWindow(spec)
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

--- Every standard window of the app, its main window first.
local function appWindows(bundleID, owns)
  local app = hs.application.get(bundleID)
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
  }

  hs.hotkey.bind(M.hyper, key, function()
    M.toggle(spec)
  end)
  return spec
end

return M
