-- A stub `hs` large enough to load the browser modules and exercise their
-- logic off-machine. Hammerspoon embeds Lua but its API is native, so nothing
-- here can be required outside the app — this substitutes the few calls the
-- modules make and records what they did.
--
-- It is not a Hammerspoon simulator. It covers the pure decisions: which
-- window belongs to which profile, what argv a launch produces, and how the
-- picker sequences. Anything involving real key capture or a real window
-- server has to be tested on the machine.

local recorded = {
  launches = {},
  alerts = {},
  binds = {},
  entered = 0,
  exited = 0,
  focused = {},
  minimized = {},
  unminimized = {},
  notified = {},
  launchOrFocus = {},
  timers = {},
  timersStopped = 0,
  filters = {},
}
_G.RECORDED = recorded

--- opts: { visible = false, minimized = true, standard = false, fullScreen = true, app = <app stub> }
function _G.mkwin(id, title, opts)
  opts = opts or {}
  local minimized = opts.minimized or false
  local owner = opts.app
  local win
  win = {
    -- Hammerspoon 1.1.1 returns 0, never nil, for an id it cannot read, so a
    -- fixture built without one behaves the same.
    id = function()
      return id or 0
    end,
    title = function()
      return title
    end,
    -- A hidden app's windows are not visible either.
    isVisible = function()
      return opts.visible ~= false and not minimized and not (owner and owner._hidden)
    end,
    isMinimized = function()
      return minimized
    end,
    isFullScreen = function()
      return opts.fullScreen == true
    end,
    -- Chromium gives every window a companion status-bar window. Those are
    -- not standard, have no id and are never minimized, so a fixture needs to
    -- be able to produce one.
    isStandard = function()
      return opts.standard ~= false
    end,
    unminimize = function()
      minimized = false
      recorded.unminimized[#recorded.unminimized + 1] = id
    end,
    minimize = function()
      minimized = true
      recorded.minimized[#recorded.minimized + 1] = id
    end,
    application = function()
      return owner
    end,
    -- mkapp calls this, so a window and its application can refer to each
    -- other without the fixture having to build them in dependency order.
    _setApp = function(app)
      owner = app
    end,
    focus = function()
      recorded.focused[#recorded.focused + 1] = id
    end,
    setFrame = function() end,
  }
  return win
end

--- An application owning a fixed set of windows.
---
--- opts: { bundle = <id>, name = <app:name()>, main = <window> }
function _G.mkapp(windows, opts)
  opts = opts or {}
  local app
  app = {
    bundleID = function()
      return opts.bundle
    end,
    name = function()
      return opts.name
    end,
    mainWindow = function()
      return opts.main
    end,
    isFrontmost = function()
      return _G.FRONTMOST == app
    end,
    _hidden = false,
    allWindows = function()
      return windows
    end,
    visibleWindows = function()
      local out = {}
      for _, w in ipairs(windows) do
        if w:isVisible() then
          out[#out + 1] = w
        end
      end
      return out
    end,
    hide = function()
      app._hidden = true
      recorded.hidden = (recorded.hidden or 0) + 1
    end,
    unhide = function()
      app._hidden = false
      recorded.unhidden = (recorded.unhidden or 0) + 1
    end,
    pid = function()
      return opts.pid
    end,
  }
  for _, w in ipairs(windows) do
    w._setApp(app)
  end
  return app
end

-- A single fake screen, wide enough that the sidebar layouts take their
-- widescreen branch.
_G.SCREEN = {
  frame = function()
    return { x = 0, y = 0, w = 3440, h = 1440 }
  end,
  name = function()
    return "Fake Display"
  end,
}

_G.APPS = {}
_G.NAMES = {}
_G.STAT = {}
_G.JSON = {}
_G.PATHS = {}
_G.FOCUSED = nil
_G.FRONTMOST = nil
_G.NOW = 1000
_G.SOURCE = "com.apple.keylayout.US"

_G.hs = {
  fs = {
    attributes = function(path)
      return _G.STAT[path]
    end,
  },
  json = {
    read = function(path)
      return _G.JSON[path]
    end,
  },
  application = {
    applicationsForBundleID = function(bundle)
      return _G.APPS[bundle] or {}
    end,
    pathForBundleID = function(bundle)
      return _G.PATHS[bundle]
    end,
    nameForBundleID = function(bundle)
      return _G.NAMES and _G.NAMES[bundle] or nil
    end,
    frontmostApplication = function()
      return _G.FRONTMOST
    end,
    get = function(bundle)
      local apps = _G.APPS[bundle]
      return apps and apps[1] or nil
    end,
    launchOrFocusByBundleID = function(bundle)
      recorded.launchOrFocus[#recorded.launchOrFocus + 1] = bundle
      return true
    end,
  },
  window = {
    focusedWindow = function()
      return _G.FOCUSED
    end,
    -- init.lua builds window filters for the per-app layout forcing. They are
    -- inert here: the point is that the file loads and its hotkeys bind, not
    -- that focus tracking works.
    filter = {
      windowFocused = "windowFocused",
      windowNotVisible = "windowNotVisible",
      windowCreated = "windowCreated",
      new = function(arg)
        local f = { arg = arg, subscribed = {} }
        function f:subscribe(event, fn)
          self.subscribed[event] = fn
          return self
        end
        function f:setAppFilter()
          return self
        end
        recorded.filters[#recorded.filters + 1] = f
        return f
      end,
    },
  },
  -- Stateful, so a test can tell the layout the user was in apart from the one
  -- a handler switched to.
  keycodes = {
    currentSourceID = function(set)
      if set then
        recorded.inputSource = set
        recorded.inputSourceSets = (recorded.inputSourceSets or 0) + 1
        _G.SOURCE = set
        return nil
      end
      return _G.SOURCE
    end,
  },
  notify = {
    new = function(spec)
      return {
        send = function()
          recorded.notified[#recorded.notified + 1] = spec and spec.title or "?"
          -- The stub swallows a config load failure into its own pcall and
          -- reports it only here, so without the body a broken init.lua fails
          -- with no reason attached.
          recorded.notifiedText = spec and spec.informativeText or nil
        end,
      }
    end,
  },
  mouse = {
    getCurrentScreen = function()
      return _G.SCREEN
    end,
  },
  geometry = {
    rect = function(x, y, w, h)
      return { x = x, y = y, w = w, h = h }
    end,
  },
  pathwatcher = {
    new = function(path, fn)
      if _G.PATHWATCHER_RAISES then
        error("pathwatcher unavailable")
      end
      recorded.watched = { path = path, fn = fn }
      return {
        start = function()
          recorded.watcherStarted = true
        end,
      }
    end,
  },
  -- The stub registers the http callback and reaches for a fallback when
  -- dispatch raises. Both are recorded rather than performed.
  urlevent = {
    openURLWithBundle = function(url, bundle)
      recorded.fallbackOpened = { url = url, bundle = bundle }
      return true
    end,
  },
  -- The full-screen fallback reads Spaces and the window server's owner list.
  -- Default: one ordinary Space, so nothing is full-screen and nothing is read.
  spaces = {
    -- The real one returns nil and a message on failure; SPACES_RAISE covers a
    -- private API that throws instead.
    allSpaces = function()
      if _G.SPACES_RAISE then
        error("spaces unavailable")
      end
      if _G.SPACES_FAIL then
        return nil, "spaces unavailable"
      end
      return _G.SPACES or { ["screen-1"] = { 1 } }
    end,
    activeSpaces = function()
      return _G.ACTIVE_SPACES or { ["screen-1"] = 1 }
    end,
    spaceType = function(id)
      return (_G.SPACE_TYPES or {})[id] or "user"
    end,
    windowsForSpace = function(id)
      return (_G.SPACE_WINDOWS or {})[id] or {}
    end,
    gotoSpace = function(id)
      recorded.wentToSpace = id
      if _G.GOTO_FAILS then
        return nil, "child is nil"
      end
      return true
    end,
  },
  execute = function(command)
    recorded.executed = (recorded.executed or 0) + 1
    recorded.lastExecuted = command
    return _G.EXECUTE_OUTPUT or "", true
  end,
  reload = function()
    recorded.reloaded = (recorded.reloaded or 0) + 1
  end,
  screen = {
    mainScreen = function()
      return _G.SCREEN
    end,
    primaryScreen = function()
      return _G.SCREEN
    end,
    allScreens = function()
      return { _G.SCREEN }
    end,
  },
  task = {
    new = function(command, _callback, args)
      return {
        start = function()
          recorded.launches[#recorded.launches + 1] = { command = command, args = args }
          return true
        end,
      }
    end,
  },
  alert = {
    -- The real signature is (str, style, screen, duration) and hs.alert
    -- shuffles: it scans the optional arguments and takes the first number as
    -- the duration. Modelling the shuffle rather than a fixed position means
    -- the duration assertion tests behaviour, not argument order — otherwise a
    -- correct refactor to the four-argument form would record a screen table
    -- as the duration and fail with a nonsense message.
    show = function(text, ...)
      local duration, style
      for _, arg in ipairs({ ... }) do
        if type(arg) == "number" and not duration then
          duration = arg
        elseif type(arg) == "table" and not style then
          style = arg
        end
      end
      recorded.alerts[#recorded.alerts + 1] = text
      recorded.alertShown = { text = text, style = style, duration = duration }
      return "alert-" .. #recorded.alerts
    end,
    closeSpecific = function(id)
      recorded.closed = id
    end,
  },
  timer = {
    secondsSinceEpoch = function()
      return _G.NOW
    end,
    -- Records enough to assert that a timer was cancelled, not merely that one
    -- was created. dismiss() stopping the timeout timer is the property that
    -- keeps a modal from outliving its alert, so a stub whose stop() does
    -- nothing would make that untestable.
    doAfter = function(seconds, fn)
      local t = { seconds = seconds, fn = fn, stopped = false }
      function t:stop()
        self.stopped = true
        recorded.timersStopped = recorded.timersStopped + 1
      end
      recorded.timers[#recorded.timers + 1] = t
      return t
    end,
  },
  hotkey = {
    bind = function(_mods, key, fn)
      recorded.binds["hyper:" .. key] = fn
    end,
    modal = {
      new = function()
        local modal = {}
        function modal:bind(mods, key, fn)
          -- Modifiers are part of the name, so a shifted binding cannot
          -- overwrite the plain one it sits beside.
          local prefix = (mods and #mods > 0) and (table.concat(mods, "+") .. "+") or ""
          recorded.binds[prefix .. key] = fn
          return self
        end
        function modal:enter()
          recorded.entered = recorded.entered + 1
        end
        function modal:exit()
          recorded.exited = recorded.exited + 1
        end
        return modal
      end,
    },
  },
}
