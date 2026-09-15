-- Behaviour tests for the browser modules, run by `nix flake check`.
--
-- The syntax gate next to this one proves the Lua parses. This proves it
-- decides correctly — above all that a window is matched to the right profile,
-- since a regression there routes a client's links into the wrong browser
-- without any visible symptom.

dofile(HARNESS)

local failures = 0

local function check(name, condition, detail)
  if condition then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" -- " .. detail) or ""))
    failures = failures + 1
  end
end

local chrome = os.getenv("HOME") .. "/Library/Application Support/Google/Chrome/Local State"
local brave = os.getenv("HOME") .. "/Library/Application Support/BraveSoftware/Brave-Browser/Local State"

STAT[chrome] = { mode = "file", modification = 1, size = 10 }
STAT[brave] = { mode = "file", modification = 1, size = 10 }

-- Shaped like the real thing: signed-in profiles carry gaia_given_name, and a
-- default-named one does not.
JSON[chrome] = {
  profile = {
    info_cache = {
      ["Default"] = { name = "Your Chrome" },
      ["Profile 1"] = { name = "acme.example", gaia_given_name = "Tapani" },
      ["Profile 2"] = { name = "Client Co", gaia_given_name = "Tapani" },
    },
  },
}
JSON[brave] = { profile = { info_cache = { ["Default"] = { name = "Personal" } } } }

local browsers = require("browsers")
local personal, company, client = browsers.targets[1], browsers.targets[2], browsers.targets[3]

print("profile names")
check("targets load from the generated table", #browsers.targets == 3, "#=" .. #browsers.targets)
check(
  "label gains the runtime profile name",
  browsers.label(company) == "Company — acme.example",
  browsers.label(company)
)
check(
  "label stays bare when the name matches the label",
  browsers.label(personal) == "Personal",
  browsers.label(personal)
)
check(
  "an unknown profile falls back to its directory",
  (function()
    local name, found = browsers.displayName({ bundle = "com.google.Chrome", profileDir = "Profile 9" })
    return name == "Profile 9" and found == false
  end)()
)
check(
  "a browser with no Local State path degrades quietly",
  (function()
    local name, found = browsers.displayName({ bundle = "org.mozilla.firefox", profileDir = "default" })
    return name == "default" and found == false
  end)()
)
check(
  "an unreadable Local State keeps the last known good",
  (function()
    local before = browsers.label(company)
    local saved = JSON[chrome]
    JSON[chrome] = nil
    STAT[chrome] = { mode = "file", modification = 2, size = 11 }
    local after = browsers.label(company)
    -- Restored, or every later Chrome read in this file is served from the
    -- stale-cache fallback rather than exercising a real parse.
    JSON[chrome] = saved
    STAT[chrome] = { mode = "file", modification = 3, size = 12 }
    return before == after
  end)(),
  "stale name should survive a failed read"
)

print("shared window helpers")
local whu = require("window-hotkey-utils")
check(
  "containsWindow never matches on a nil id",
  (function()
    -- Chromium keeps helper windows whose AX id cannot be read. Comparing two
    -- nils would report an unrelated window as a match.
    local noId = mkwin(nil, "helper")
    local other = mkwin(nil, "another helper")
    return whu.containsWindow({ noId }, other) == false
  end)()
)
check(
  "containsWindow matches by id, not identity",
  (function()
    return whu.containsWindow({ mkwin(70, "a") }, mkwin(70, "different title")) == true
      and whu.containsWindow({ mkwin(70, "a") }, mkwin(71, "a")) == false
  end)()
)
check(
  "applyLayout is a no-op without a layout function",
  (function()
    -- nil layoutFn is how a toggle-only binding is expressed, so this must not
    -- reposition rather than erroring.
    return whu.applyLayout(mkwin(72, "x"), nil) == false and whu.applyLayout(nil, function() end) == false
  end)()
)

print("window matching")
local chromeWins = {
  mkwin(1, "Some page - Google Chrome - Tapani (acme.example)"),
  mkwin(2, "Other - Google Chrome - Tapani (Client Co)"),
}
-- An automation copy driven with its own --user-data-dir. Same bundle id, same
-- bundle path, and its titles carry no profile suffix at all.
local automationWins = { mkwin(3, "devtools harness - Google Chrome") }
APPS["com.google.Chrome"] = { mkapp(chromeWins), mkapp(automationWins) }
APPS["com.brave.Browser"] = { mkapp({ mkwin(10, "x - Brave"), mkwin(11, "y - Brave") }) }

check(
  "a non-standard companion window is never a browser window",
  (function()
    -- Chromium gives every window a status-bar companion. It has no id and is
    -- never minimized, so unfiltered it is selected as "the" window whenever the
    -- real one is minimized, and the hotkey goes dead.
    local real = mkwin(40, "page - Brave", { minimized = true })
    local helper = mkwin(nil, "page - Brave", { standard = false })
    APPS["com.brave.Browser"] = { mkapp({ helper, real }) }
    local found = browsers.windowsFor(personal)
    APPS["com.brave.Browser"] = { mkapp({ mkwin(10, "x - Brave"), mkwin(11, "y - Brave") }) }
    return #found == 1 and found[1]:id() == 40
  end)()
)
check(
  "one profile name being a suffix of another does not steal its windows",
  (function()
    STAT[brave] = { mode = "file", modification = 9, size = 90 }
    JSON[brave] = {
      profile = {
        info_cache = {
          -- The LONGER name sits on the earlier-sorting directory on purpose,
          -- so "last match wins" and "longest match wins" disagree. With them
          -- the other way round the two rules are indistinguishable here.
          ["Default"] = { name = "Client Work" },
          ["Profile 7"] = { name = "Work" },
        },
      },
    }
    APPS["com.brave.Browser"] = { mkapp({ mkwin(50, "page - Brave - Client Work") }) }
    local longer = browsers.windowsFor({ bundle = "com.brave.Browser", profileDir = "Default", label = "C" })
    local shorter = browsers.windowsFor({ bundle = "com.brave.Browser", profileDir = "Profile 7", label = "W" })
    STAT[brave] = { mode = "file", modification = 10, size = 91 }
    JSON[brave] = { profile = { info_cache = { ["Default"] = { name = "Personal" } } } }
    APPS["com.brave.Browser"] = { mkapp({ mkwin(10, "x - Brave"), mkwin(11, "y - Brave") }) }
    return #shorter == 0 and #longer == 1
  end)(),
  "longest matching tail must win"
)
check(
  "a profile with no GAIA name is matched by its bare name",
  (function()
    APPS["com.google.Chrome"] = { mkapp({ mkwin(60, "page - Google Chrome - Your Chrome") }) }
    local found = browsers.windowsFor({ bundle = "com.google.Chrome", profileDir = "Default", label = "D" })
    APPS["com.google.Chrome"] = { mkapp(chromeWins), mkapp(automationWins) }
    return #found == 1 and found[1]:id() == 60
  end)()
)

local companyWins = browsers.windowsFor(company)
local clientWins = browsers.windowsFor(client)
check("company matches only its own window", #companyWins == 1 and companyWins[1]:id() == 1, "#=" .. #companyWins)
check("client matches only its own window", #clientWins == 1 and clientWins[1]:id() == 2, "#=" .. #clientWins)
check(
  "a suffix-less automation window matches no profile",
  (function()
    for _, w in ipairs(companyWins) do
      if w:id() == 3 then
        return false
      end
    end
    for _, w in ipairs(clientWins) do
      if w:id() == 3 then
        return false
      end
    end
    return true
  end)(),
  "Chrome knows 3 profiles, so a bare title is unknown, not Default"
)
check("a single-profile browser matches all its windows", #browsers.windowsFor(personal) == 2)

check(
  "a bundle with no Local State path is reported as unknown, not as one profile",
  (function()
    local _, count, known = browsers.profiles("com.example.NotABrowser")
    return count == 0 and known == false
  end)(),
  "otherwise every window matches every target"
)
check(
  "a readable single-profile browser is reported as known",
  (function()
    local _, count, known = browsers.profiles("com.brave.Browser")
    return count == 1 and known == true
  end)()
)

print("toggling")
check(
  "a minimized window is restored, not just focused",
  (function()
    local win = mkwin(20, "z - Brave", { minimized = true })
    local app = mkapp({ win })
    APPS["com.brave.Browser"] = { app }
    FOCUSED = nil
    local before = #RECORDED.launches
    browsers.toggle(personal, nil)
    -- allWindows counts minimized windows, so without unminimize this focuses a
    -- window the window server will not raise and the hotkey goes dead.
    return #RECORDED.unminimized == 1
      and RECORDED.unminimized[1] == 20
      and RECORDED.focused[#RECORDED.focused] == 20
      and #RECORDED.launches == before
  end)()
)
check(
  "hiding is used when the app has no other visible window",
  (function()
    local win = mkwin(21, "only - Brave")
    local app = mkapp({ win })
    APPS["com.brave.Browser"] = { app }
    FOCUSED = win
    local hiddenBefore = RECORDED.hidden or 0
    browsers.toggle(personal, nil)
    return (RECORDED.hidden or 0) == hiddenBefore + 1 and #RECORDED.minimized == 0
  end)()
)
check(
  "minimizing is used when another profile's window is still visible",
  (function()
    local mine = mkwin(22, "Some page - Google Chrome - Tapani (acme.example)")
    local theirs = mkwin(23, "Other - Google Chrome - Tapani (Client Co)")
    APPS["com.google.Chrome"] = { mkapp({ mine, theirs }) }
    FOCUSED = mine
    local hiddenBefore = RECORDED.hidden or 0
    browsers.toggle(company, nil)
    -- app:hide() would take the client's window down with it.
    return #RECORDED.minimized == 1 and RECORDED.minimized[1] == 22 and (RECORDED.hidden or 0) == hiddenBefore
  end)()
)
check(
  "an empty profile with no windows launches",
  (function()
    APPS["com.google.Chrome"] = {}
    FOCUSED = nil
    local before = #RECORDED.launches
    browsers.toggle(company, nil)
    return #RECORDED.launches == before + 1
  end)()
)

print("one toggle for apps and profiles")

--- An app hotkey under test, with its app registered the way hs.application.get
--- would find it. Keys are not real hotkeys, so nothing here collides with the
--- bindings init.lua makes later.
local function appHotkey(key, bundle, windows, opts)
  opts = opts or {}
  local app = mkapp(windows, { bundle = bundle, name = opts.name, main = opts.main, pid = opts.pid })
  APPS[bundle] = { app }
  local spec = whu.bindToggle(key, bundle, opts.layout, opts.bind)
  return spec, app
end

local noLayout = function()
  return { x = 0, y = 0, w = 1, h = 1 }
end

check(
  "a press changes no input source itself",
  (function()
    -- Set at press time the layout lands under the app still being typed in,
    -- and ahead of windowFocused, which then records the forced layout as the
    -- one to go back to.
    SOURCE = whu.fiProg
    local setsBefore = RECORDED.inputSourceSets or 0
    local spec = appHotkey("t1", "com.example.Launch", {}, { layout = noLayout })
    FOCUSED = nil
    whu.toggle(spec)
    local raiseWin = mkwin(301, "raise")
    local raiseSpec = appHotkey("t2", "com.example.Raise", { raiseWin }, { main = raiseWin })
    whu.toggle(raiseSpec)
    return (RECORDED.inputSourceSets or 0) == setsBefore
  end)()
)

check(
  "a raised window's layout waits for its focus, and a different app's focus leaves it waiting",
  (function()
    NOW = 2000
    local win = mkwin(302, "w")
    local spec, app = appHotkey("t3", "com.example.Wait", { win }, { main = win })
    whu.toggle(spec)
    local other = mkapp({}, { bundle = "com.example.Other" })
    local early = whu.claimInputSource(other)
    local claimed = whu.claimInputSource(app)
    local again = whu.claimInputSource(app)
    return early == nil and claimed == whu.fiProg and again == nil
  end)(),
  "only the focus the press was waiting for consumes it"
)

check(
  "a layout request expires rather than applying to some later click",
  (function()
    NOW = 3000
    local app = mkapp({}, { bundle = "com.example.Stale" })
    whu.requestInputSource("com.example.Stale", whu.us)
    NOW = 3000 + whu.intentTTL + 1
    return whu.claimInputSource(app) == nil
  end)()
)

check(
  "the input-source retry is held, and a later set stops the earlier retry",
  (function()
    local base = #RECORDED.timers
    whu.setInputSource(whu.us)
    local first = RECORDED.timers[base + 1]
    whu.setInputSource(whu.fiProg)
    local second = RECORDED.timers[base + 2]
    return first ~= nil
      and second ~= nil
      and whu._inputRetry == second
      and first.stopped == true
      and second.stopped == false
  end)(),
  "an unheld retry is collectable; an unstopped one re-asserts a superseded layout"
)

check(
  "an app launch's reposition timer is held",
  (function()
    local spec = appHotkey("t4", "com.example.Held", {}, { layout = noLayout })
    FOCUSED = nil
    local base = #RECORDED.timers
    whu.toggle(spec)
    local timer = RECORDED.timers[base + 1]
    return timer ~= nil and timer.seconds == 1.5 and whu._pending[spec.id] == timer
  end)(),
  "unreferenced, a collection inside the delay loses the positioning"
)

check(
  "no reposition timer when nothing would be positioned",
  (function()
    local base = #RECORDED.timers
    FOCUSED = nil
    whu.toggle(appHotkey("t5", "com.example.NoLayout", {}, {}))
    local watched = appHotkey("t6", "com.example.Watched", {}, { layout = noLayout, bind = { watchCreate = true } })
    whu.toggle(watched)
    -- The watchCreate filter positions every new window; a timer as well would
    -- move it a second time, 1.5s after the user may have moved it.
    return #RECORDED.timers == base
  end)()
)

check(
  "any later press cancels a pending launch reposition",
  (function()
    local win = mkwin(303, "arrived")
    local spec, app = appHotkey("t7", "com.example.Cancel", {}, { layout = noLayout })
    FOCUSED = nil
    local base = #RECORDED.timers
    whu.toggle(spec)
    local timer = RECORDED.timers[base + 1]
    -- The window has arrived; the second press takes the raise path, and the
    -- armed timer would otherwise reposition whatever is listed first.
    APPS["com.example.Cancel"] = { mkapp({ win }, { bundle = "com.example.Cancel", main = win }) }
    whu.toggle(spec)
    local _ = app
    return timer ~= nil and timer.stopped == true and whu._pending[spec.id] == nil
  end)()
)

check(
  "a browser profile's pending launch is cancelled by a press that focuses",
  (function()
    local layout = noLayout
    APPS["com.brave.Browser"] = {}
    FOCUSED = nil
    local base = #RECORDED.timers
    browsers.toggle(personal, layout)
    local timer = RECORDED.timers[base + 1]
    APPS["com.brave.Browser"] = { mkapp({ mkwin(304, "new - Brave") }, { bundle = "com.brave.Browser" }) }
    browsers.toggle(personal, layout)
    return timer ~= nil and timer.stopped == true
  end)()
)

check(
  "a browser launch asks for the typing layout too",
  (function()
    NOW = 4000
    APPS["com.google.Chrome"] = {}
    FOCUSED = nil
    browsers.toggle(company, nil)
    return whu.claimInputSource(mkapp({}, { bundle = "com.google.Chrome" })) == whu.fiProg
  end)(),
  "the launch path used to skip it, leaving browsers inconsistent with apps"
)

check(
  "a focused window the enumeration misses is put away, not duplicated",
  (function()
    -- A full-screen window drops out of allWindows() while focusedWindow()
    -- still returns it.
    local full = mkwin(305, "full", { fullScreen = true })
    local spec, app = appHotkey("t8", "com.example.Full", {}, {})
    full._setApp(app)
    FOCUSED = full
    local launchesBefore = #RECORDED.launchOrFocus
    local hiddenBefore = RECORDED.hidden or 0
    whu.toggle(spec)
    return #RECORDED.launchOrFocus == launchesBefore and (RECORDED.hidden or 0) == hiddenBefore + 1
  end)()
)

check(
  "a full-screen window hides even beside another visible window",
  (function()
    -- It cannot minimize, so the minimize branch would do nothing at all.
    local full = mkwin(306, "Page - Google Chrome - Tapani (acme.example)", { fullScreen = true })
    local theirs = mkwin(307, "Other - Google Chrome - Tapani (Client Co)")
    APPS["com.google.Chrome"] = { mkapp({ theirs, full }, { bundle = "com.google.Chrome" }) }
    FOCUSED = full
    local hiddenBefore = RECORDED.hidden or 0
    local minimizedBefore = #RECORDED.minimized
    browsers.toggle(company, nil)
    return (RECORDED.hidden or 0) == hiddenBefore + 1 and #RECORDED.minimized == minimizedBefore
  end)()
)

check(
  "a companion window does not count as another profile's",
  (function()
    local mine = mkwin(308, "only - Brave")
    local helper = mkwin(nil, "only - Brave", { standard = false })
    APPS["com.brave.Browser"] = { mkapp({ mine, helper }, { bundle = "com.brave.Browser" }) }
    FOCUSED = mine
    local hiddenBefore = RECORDED.hidden or 0
    local minimizedBefore = #RECORDED.minimized
    browsers.toggle(personal, nil)
    return (RECORDED.hidden or 0) == hiddenBefore + 1 and #RECORDED.minimized == minimizedBefore
  end)(),
  "its nil id never matches, so it would always force a minimize"
)

check(
  "a focused window of another profile is not claimed",
  (function()
    local theirs = mkwin(309, "Other - Google Chrome - Tapani (Client Co)")
    mkapp({ theirs }, { bundle = "com.google.Chrome" })
    local wrongBundle = mkwin(310, "x - Tapani (acme.example)")
    mkapp({ wrongBundle }, { bundle = "com.example.NotChrome" })
    return browsers.owns(company, theirs) == false
      and browsers.owns(client, theirs) == true
      and browsers.owns(company, wrongBundle) == false
  end)()
)

check(
  "an app hotkey puts its focused window away and raises otherwise",
  (function()
    local win = mkwin(311, "slack", { minimized = true })
    local spec = appHotkey("t9", "com.example.Chat", { win }, {})
    FOCUSED = nil
    local unminBefore = #RECORDED.unminimized
    whu.toggle(spec)
    local raised = #RECORDED.unminimized == unminBefore + 1 and RECORDED.focused[#RECORDED.focused] == 311
    FOCUSED = win
    local hiddenBefore = RECORDED.hidden or 0
    whu.toggle(spec)
    return raised and (RECORDED.hidden or 0) == hiddenBefore + 1
  end)(),
  "a minimized-only app used to fall through to launchOrFocus"
)

print("full-screen windows on another Space")

--- One ordinary Space and one full-screen Space holding window 900, owned by
--- pid 77.
local function fullScreenSpace()
  SPACES = { ["screen-1"] = { 1, 50 } }
  SPACE_TYPES = { [50] = "fullscreen" }
  SPACE_WINDOWS = { [50] = { 899, 900 } }
  EXECUTE_OUTPUT = "12 5\n900 77\n899 3\n"
end

local function noFullScreenSpace()
  SPACES, SPACE_TYPES, SPACE_WINDOWS, EXECUTE_OUTPUT = nil, nil, nil, nil
end

check(
  "no owner lookup runs unless a full-screen Space exists",
  (function()
    noFullScreenSpace()
    local executedBefore = RECORDED.executed or 0
    local launchesBefore = #RECORDED.launchOrFocus
    FOCUSED = nil
    whu.toggle(appHotkey("t11", "com.example.Plain", {}, { pid = 77 }))
    return (RECORDED.executed or 0) == executedBefore and #RECORDED.launchOrFocus == launchesBefore + 1
  end)(),
  "the lookup spawns osascript, so the common launch must not pay for it"
)

check(
  "an app's full-screen window elsewhere is gone to, not duplicated",
  (function()
    fullScreenSpace()
    RECORDED.wentToSpace = nil
    local launchesBefore = #RECORDED.launchOrFocus
    local timersBefore = #RECORDED.timers
    FOCUSED = nil
    whu.toggle(appHotkey("t12", "com.example.FullElsewhere", {}, { pid = 77, layout = noLayout }))
    noFullScreenSpace()
    -- No reposition either: a full-screen window has no frame to set.
    return RECORDED.wentToSpace == 50 and #RECORDED.launchOrFocus == launchesBefore and #RECORDED.timers == timersBefore
  end)()
)

check(
  "the owner lookup survives sh's single quotes",
  (function()
    -- hs.execute runs through sh. A quote inside the script ends the argument
    -- early, osascript gets half a program, and every lookup finds no owner.
    local command = RECORDED.lastExecuted or ""
    local _, quotes = command:gsub("'", "")
    return quotes == 2 and command:find("^/usr/bin/osascript %-l JavaScript %-e '") ~= nil
  end)(),
  tostring(RECORDED.lastExecuted)
)

check(
  "a full-screen Space owned by some other process is not gone to",
  (function()
    fullScreenSpace()
    RECORDED.wentToSpace = nil
    local launchesBefore = #RECORDED.launchOrFocus
    FOCUSED = nil
    whu.toggle(appHotkey("t13", "com.example.NotOwner", {}, { pid = 78 }))
    noFullScreenSpace()
    return RECORDED.wentToSpace == nil and #RECORDED.launchOrFocus == launchesBefore + 1
  end)()
)

check(
  "one profile of several never goes to a full-screen window it cannot attribute",
  (function()
    -- Chrome's process owns both profiles' windows, so the pid says nothing
    -- about which profile a full-screen one is.
    fullScreenSpace()
    RECORDED.wentToSpace = nil
    APPS["com.google.Chrome"] = { mkapp({}, { bundle = "com.google.Chrome", pid = 77 }) }
    FOCUSED = nil
    local launchesBefore = #RECORDED.launches
    browsers.toggle(company, nil)
    local multi = RECORDED.wentToSpace == nil and #RECORDED.launches == launchesBefore + 1

    -- Brave knows one profile, so its process does identify the window.
    APPS["com.brave.Browser"] = { mkapp({}, { bundle = "com.brave.Browser", pid = 77 }) }
    browsers.toggle(personal, nil)
    noFullScreenSpace()
    return multi and RECORDED.wentToSpace == 50
  end)()
)

check(
  "a Spaces failure falls back to launching",
  (function()
    fullScreenSpace()
    SPACES_RAISE = true
    local launchesBefore = #RECORDED.launchOrFocus
    FOCUSED = nil
    local ok = pcall(whu.toggle, appHotkey("t14", "com.example.SpacesDown", {}, { pid = 77 }))
    SPACES_RAISE = nil
    noFullScreenSpace()
    return ok and #RECORDED.launchOrFocus == launchesBefore + 1
  end)(),
  "hs.spaces rests on private APIs; a raise there must not kill the hotkey"
)

check(
  "new windows are matched by bundle id, not by the name LaunchServices reports",
  (function()
    -- nameForBundleID says "Chrome" where app:name() says "Google Chrome"; a
    -- filter built from the first matches no window at all.
    NAMES["com.example.Named"] = "Short"
    local filtersBefore = #RECORDED.filters
    appHotkey("t10", "com.example.Named", {}, { layout = noLayout, bind = { watchCreate = true } })
    local filter = RECORDED.filters[filtersBefore + 1]
    if not filter or type(filter.arg) ~= "function" then
      return false
    end
    local win = mkwin(312, "term")
    mkapp({ win }, { bundle = "com.example.Named", name = "Long Name" })
    local stranger = mkwin(313, "term")
    mkapp({ stranger }, { bundle = "com.example.Else", name = "Short" })
    return filter.arg(win) == true
      and filter.arg(stranger) == false
      and filter.subscribed[hs.window.filter.windowCreated] ~= nil
  end)()
)

print("launching")
PATHS["com.google.Chrome"] = "/Applications/Google Chrome.app"
browsers.launch(company, "https://example.com/x")
local launch = RECORDED.launches[#RECORDED.launches]
local argv = table.concat(launch.args, " ")
check("runs open by absolute path", launch.command == "/usr/bin/open")
check("passes -n, without which --args is dropped", launch.args[1] == "-n", argv)
check(
  "targets the app by path when one resolves",
  launch.args[2] == "-a" and launch.args[3] == "/Applications/Google Chrome.app",
  argv
)
check("carries the profile directory", argv:find("--profile%-directory=Profile 1") ~= nil, argv)
check("puts the url last", launch.args[#launch.args] == "https://example.com/x", argv)
check(
  "falls back to the bundle id when no path resolves",
  (function()
    PATHS["com.google.Chrome"] = nil
    browsers.launch(client, nil)
    local l = RECORDED.launches[#RECORDED.launches]
    return l.args[2] == "-b" and l.args[3] == "com.google.Chrome"
  end)()
)
check(
  "omits the url entirely when opening a bare profile",
  (function()
    local l = RECORDED.launches[#RECORDED.launches]
    return l.args[#l.args] == "--profile-directory=Profile 2"
  end)()
)

check(
  "a url on a profile-less target is opened, not passed as argv",
  (function()
    PATHS["com.apple.Safari"] = "/Applications/Safari.app"
    browsers.launch({ bundle = "com.apple.Safari", label = "Safari" }, "https://example.com/s")
    local l = RECORDED.launches[#RECORDED.launches]
    local joined = table.concat(l.args, " ")
    -- open(1): everything after --args is handed to the app as argv and is "not
    -- opened or interpreted by the open tool". Only Chromium reads a URL back
    -- out of argv, so any other browser would drop the link entirely. -n would
    -- also force a real second instance of a browser with no singleton.
    return joined:find("%-%-args") == nil and l.args[1] ~= "-n" and l.args[#l.args] == "https://example.com/s"
  end)()
)
check(
  "omits -n for a target with neither profile nor url",
  (function()
    PATHS["com.apple.Safari"] = "/Applications/Safari.app"
    browsers.launch({ bundle = "com.apple.Safari", label = "Safari" }, nil)
    local l = RECORDED.launches[#RECORDED.launches]
    -- -n on a browser with no singleton to collapse it forces a real second copy.
    return l.args[1] ~= "-n" and l.args[1] == "-a"
  end)()
)

print("picker")
local picker = require("picker")
picker.setup()
check("binds one plain key per target", RECORDED.binds["b"] and RECORDED.binds["v"] and RECORDED.binds["c"] ~= nil)
check("binds escape", RECORDED.binds["escape"] ~= nil)

picker.present("https://one.example")
check("shows an alert for the first link", #RECORDED.alerts == 1)
check("enters the modal once", RECORDED.entered == 1)
check("lists every target", RECORDED.alerts[1]:find("Company") ~= nil, RECORDED.alerts[1])
-- The modal holds the keyboard for picker.timeout. If the alert is given a
-- shorter life the machine captures every keystroke with nothing on screen
-- explaining why — which is what happens when a nil screen argument truncates
-- hs.alert's ipairs scan and the duration silently falls back to 2s.
check(
  "the alert outlives the modal",
  RECORDED.alertShown
    and type(RECORDED.alertShown.duration) == "number"
    and RECORDED.alertShown.duration > picker.timeout,
  "duration="
    .. tostring(RECORDED.alertShown and RECORDED.alertShown.duration)
    .. " timeout="
    .. tostring(picker.timeout)
)
check("the alert is styled, not defaulted", RECORDED.alertShown and type(RECORDED.alertShown.style) == "table")

picker.present("https://two.example")
check("a second link reopens the alert", #RECORDED.alerts == 2)
check("a second link does not re-enter the modal", RECORDED.entered == 1, "entered=" .. RECORDED.entered)
check("a second link shows the queue depth", RECORDED.alerts[2]:find("2 links queued") ~= nil, RECORDED.alerts[2])

local before = #RECORDED.launches
local exitedBefore = RECORDED.exited
local stoppedBefore = RECORDED.timersStopped
RECORDED.binds["v"]()
check("one choice opens every queued link", #RECORDED.launches - before == 2, "delta=" .. (#RECORDED.launches - before))
check("choosing exits the modal", RECORDED.exited == exitedBefore + 1, "delta=" .. (RECORDED.exited - exitedBefore))
-- The timeout timer must be cancelled, not merely dropped. A live timer would
-- fire after the choice and open every queued link a second time.
check("choosing cancels the timeout timer", RECORDED.timersStopped > stoppedBefore, "no timer was stopped")
-- Nothing else asserts the queue is emptied, so choose() could iterate it in
-- place and re-open every earlier link on the next choice.
local afterChoice = #RECORDED.launches
RECORDED.binds["c"]()
check("choosing again opens nothing, because the queue was emptied", #RECORDED.launches == afterChoice)

picker.present("https://three.example")
local afterEscape = #RECORDED.launches
local exitedBeforeEscape = RECORDED.exited
RECORDED.binds["escape"]()
check("escape opens nothing", #RECORDED.launches == afterEscape)
-- Without this, escape could stop dismissing and the modal would stay entered,
-- swallowing b/v/c/escape machine-wide until the timeout fired.
check(
  "escape exits the modal",
  RECORDED.exited == exitedBeforeEscape + 1,
  "delta=" .. (RECORDED.exited - exitedBeforeEscape)
)

local timersBefore = #RECORDED.timers
picker.present("https://four.example")
check("escape cleared the queue", RECORDED.alerts[#RECORDED.alerts]:find("queued") == nil)
local countdown = RECORDED.timers[timersBefore + 1]
local beforeTimeout = #RECORDED.launches
countdown.fn()
check("the timeout routes rather than dropping the link", #RECORDED.launches - beforeTimeout == 1)
check("the countdown runs for picker.timeout", countdown.seconds == picker.timeout, tostring(countdown.seconds))
-- A timeout raised past the ceiling would make itself unreachable: the ceiling
-- would pre-empt every countdown, and one ordinary link would hold the keyboard
-- for the whole minute.
check(
  "the countdown runs out before the ceiling, and the ceiling stays inside a minute",
  picker.timeout < picker.maxHold and picker.maxHold <= 60,
  "timeout=" .. tostring(picker.timeout) .. " maxHold=" .. tostring(picker.maxHold)
)

check(
  "an empty target list raises rather than swallowing the link",
  (function()
    local saved = browsers.targets
    browsers.targets = {}
    local ok = pcall(picker.present, "https://lost.example")
    browsers.targets = saved
    -- Raising is what reaches the stub's hard-coded openURLWithBundle fallback.
    return ok == false
  end)()
)

print("picker queue")
-- Two timers per picker: the countdown, which every later link restarts, and
-- the ceiling, which nothing does.
local queueBase = #RECORDED.timers
picker.present("https://q1.example")
local firstCountdown = RECORDED.timers[queueBase + 1]
local ceiling = RECORDED.timers[queueBase + 2]
check(
  "a first link arms a countdown and a ceiling",
  #RECORDED.timers == queueBase + 2
    and firstCountdown ~= nil
    and firstCountdown.seconds == picker.timeout
    and ceiling ~= nil
    and ceiling.seconds == picker.maxHold,
  "armed " .. (#RECORDED.timers - queueBase) .. " timers"
)

picker.present("https://q2.example")
local refreshed = RECORDED.timers[queueBase + 3]
-- Without the refresh, a link clicked at the end of the countdown leaves a
-- fraction of a second to read the rows and choose for it.
check(
  "a second link refreshes the countdown",
  firstCountdown ~= nil
    and firstCountdown.stopped == true
    and refreshed ~= nil
    and refreshed ~= firstCountdown
    and refreshed.seconds == picker.timeout,
  "old stopped="
    .. tostring(firstCountdown and firstCountdown.stopped)
    .. " new="
    .. tostring(refreshed and refreshed.seconds)
)
-- The refresh is what makes a ceiling necessary. If a link re-armed it too,
-- links arriving faster than the countdown would hold every bound key
-- machine-wide for as long as they kept coming.
check(
  "the ceiling is armed once and no link re-arms it",
  ceiling ~= nil and ceiling.stopped == false and #RECORDED.timers == queueBase + 3,
  "armed " .. (#RECORDED.timers - queueBase) .. " timers, ceiling stopped=" .. tostring(ceiling and ceiling.stopped)
)

local beforeCeiling = #RECORDED.launches
if ceiling then
  ceiling.fn()
end
-- The ceiling ends the picker, not one link of it, and it routes for the same
-- reason the countdown does: a dropped link leaves the user with nothing.
check(
  "the ceiling routes the whole queue rather than dropping it",
  #RECORDED.launches - beforeCeiling == 2,
  "delta=" .. (#RECORDED.launches - beforeCeiling)
)
-- A countdown left armed would fire after the ceiling had already routed and
-- open a queue that no longer exists.
check("the ceiling cancels the countdown it pre-empted", refreshed ~= nil and refreshed.stopped == true)

-- A raise while reopening must never leave the modal holding the keyboard with
-- nothing on screen: the alert is what tells the user why their keys stopped
-- working, and the picker is deliberately kept alive on this path.
picker.present("https://onscreen-one.example")
-- The harness hands back "alert-N", so the id of the alert currently on screen
-- is recoverable and can be checked against what closeSpecific was given.
local liveAlert = "alert-" .. #RECORDED.alerts
local enteredBefore = RECORDED.entered
RECORDED.closed = nil
local savedLabel2 = browsers.label
browsers.label = function()
  error("label unavailable")
end
pcall(picker.present, "https://onscreen-two.example")
browsers.label = savedLabel2
check(
  "a raise while reopening leaves the alert up",
  RECORDED.closed ~= liveAlert,
  "closed " .. tostring(RECORDED.closed) .. " with the modal still entered"
)

-- present() and offer() once disagreed about whether a picker was up — one read
-- the timer, the other the alert — so a link after this re-entered the modal.
picker.present("https://onscreen-three.example")
check(
  "a link after a reopen-raise does not re-enter the modal",
  RECORDED.entered == enteredBefore,
  "entered " .. RECORDED.entered .. ", expected " .. enteredBefore
)
RECORDED.binds["escape"]()

-- A nil url would append nothing and then hold the keyboard over an empty queue
-- until the countdown opened nothing at all.
local nilRaised = pcall(picker.present, nil)
check("a nil url raises rather than entering a modal", not nilRaised)
check("a nil url leaves no picker up", RECORDED.entered == enteredBefore)

-- The other direction. An answered picker that leaves its ceiling armed hands
-- the next picker's queue to targets[1] when that ceiling runs out, in place of
-- the choice its user was making.
local answeredBase = #RECORDED.timers
picker.present("https://answered.example")
local answeredCeiling = RECORDED.timers[answeredBase + 2]
RECORDED.binds["v"]()
check("choosing stops the ceiling", answeredCeiling ~= nil and answeredCeiling.stopped == true)

local escapedBase = #RECORDED.timers
picker.present("https://escaped.example")
local escapedCeiling = RECORDED.timers[escapedBase + 2]
RECORDED.binds["escape"]()
check("escape stops the ceiling", escapedCeiling ~= nil and escapedCeiling.stopped == true)

-- A raise while a picker is already up must cost only the link that raised.
-- Draining here would lose the earlier links with nothing on screen to say so.
picker.present("https://keep-one.example")
picker.present("https://keep-two.example")
local savedLabel = browsers.label
browsers.label = function()
  error("label unavailable")
end
local reopenRaised = pcall(picker.present, "https://raises.example")
browsers.label = savedLabel
check("a raise on a reopening picker still propagates", not reopenRaised)

local keptBefore = #RECORDED.launches
RECORDED.binds["v"]()
check(
  "the links queued before the raise survive it",
  #RECORDED.launches == keptBefore + 2,
  "opened " .. (#RECORDED.launches - keptBefore) .. ", expected the two queued before the raise"
)
check(
  "the link that raised is not opened twice",
  (function()
    for i = keptBefore + 1, #RECORDED.launches do
      local args = RECORDED.launches[i].args
      if args[#args] == "https://raises.example" then
        return false
      end
    end
    return true
  end)()
)

check(
  "a raise while offering drains the queue rather than holding the link",
  (function()
    -- The rows carry profile names read off disk, so this section really can
    -- raise. When it does, the raise reaches the stub's fallback and the link
    -- is opened there; a queue still holding it opens it a second time, in a
    -- different profile, on the next link's keypress.
    local realLabel = browsers.label
    browsers.label = function()
      error("Local State unreadable", 0)
    end
    local offered = pcall(picker.present, "https://raised.example")
    browsers.label = realLabel
    if offered then
      return false
    end

    local before = #RECORDED.launches
    picker.present("https://next.example")
    local queued = RECORDED.alerts[#RECORDED.alerts]:find("queued") ~= nil
    RECORDED.binds["b"]()
    return not queued and #RECORDED.launches - before == 1
  end)(),
  "the raised link must reach the fallback only"
)

print("router")
local router = require("router")
local beforeRouter = #RECORDED.launches
local alertsBefore = #RECORDED.alerts
-- host is nil for a file:// URL. A router that indexed it would throw here,
-- and the throw would reach the stub's fallback on every single link.
local ok = pcall(router.dispatch, "file", nil, {}, "file:///tmp/x.html", -1)
check("a nil host does not throw", ok)
check("the router does not open anything itself", #RECORDED.launches == beforeRouter)
-- A delta, not a cumulative count: earlier checks leave alerts behind, so a
-- cumulative assertion passes even when dispatch does nothing. present(nil) is
-- a silent no-op on the queue, so a wrong argument has to be caught here too.
check("the router raises exactly one picker", #RECORDED.alerts == alertsBefore + 1)
check(
  "the router hands the picker the full url",
  (function()
    local queuedBefore = #RECORDED.launches
    RECORDED.binds["b"]()
    local l = RECORDED.launches[#RECORDED.launches]
    return #RECORDED.launches == queuedBefore + 1 and l.args[#l.args] == "file:///tmp/x.html"
  end)(),
  "the dispatched url never reached a launch"
)

print("generated stub")

-- STUBLUA is the real generated init.lua, built by nix with test values. It is
-- the only file whose failure loses every clicked link on the machine, and
-- nothing else in the build executes it: home.file receives the built store
-- path unread. Loaded last, because it registers a path watcher and reassigns
-- hs.urlevent.httpCallback.
-- bindToggle's watchCreate path looks this up while init.lua loads.
NAMES["com.mitchellh.ghostty"] = "Ghostty"

if not STUBLUA then
  check("STUBLUA was passed to the spec", false, "the flake check must build the stub and pass its path")
else
  hs.configdir = STUBCFGDIR

  local notifiedBefore = #RECORDED.notified
  local stubLoaded, stubErr = pcall(dofile, STUBLUA)
  check("the generated stub loads", stubLoaded, tostring(stubErr))

  --- Did the stub emit this notification since it started loading?
  local function notifiedSince(title, from)
    for i = from + 1, #RECORDED.notified do
      if RECORDED.notified[i] == title then
        return true
      end
    end
    return false
  end

  if stubLoaded then
    check("it registers an http callback", type(hs.urlevent.httpCallback) == "function")

    -- The load-time pcall reports failure through a notification and nothing
    -- else, so a config that throws leaves the stub looking healthy: callback
    -- registered, watcher running, no hotkeys. The hotkey assertions further
    -- down are what make this falsifiable.
    check(
      "it brings up the hand-written config",
      not notifiedSince("Hammerspoon config failed to load", notifiedBefore) and package.loaded["lua.init"] ~= nil,
      tostring(RECORDED.notifiedText)
    )
    -- A bare require("init") resolves back through Hammerspoon's own
    -- <configdir>/?.lua template to the stub itself and recurses until the
    -- stack blows, which the pcall then reports as success. The module key is
    -- the only visible difference between that and a correct load.
    check("it requires the config by its dotted name", package.loaded["init"] == nil)
    check("it opens the ipc port activation reloads through", RECORDED.ipcRequired == true)
    check("it puts its own lua/ on package.path", package.path:find(hs.configdir .. "/lua/?.lua", 1, true) ~= nil)
    check(
      "it reports no configdir drift when the path matches",
      not notifiedSince("Hammerspoon config dir drift", notifiedBefore)
    )

    check("it starts the reload watcher", RECORDED.watcherStarted == true)
    check(
      "the watcher watches lua/, not the config root",
      RECORDED.watched and RECORDED.watched.path == hs.configdir .. "/lua",
      RECORDED.watched and RECORDED.watched.path
    )

    -- The debounce is the only real branching in the stub: a non-Lua write must
    -- not reload, and a second write must replace the pending timer rather than
    -- queue another reload behind it.
    local timersBefore = #RECORDED.timers
    RECORDED.watched.fn({ "notes.txt" })
    check("a non-Lua write arms nothing", #RECORDED.timers == timersBefore)

    RECORDED.watched.fn({ "picker.lua" })
    check("a Lua write arms a reload", #RECORDED.timers == timersBefore + 1)
    local pending = RECORDED.timers[#RECORDED.timers]
    check("the reload is debounced, not immediate", pending.seconds > 0 and RECORDED.reloaded == nil)

    local stoppedBefore = RECORDED.timersStopped
    RECORDED.watched.fn({ "browsers.lua" })
    check("a second write replaces the pending reload", RECORDED.timersStopped == stoppedBefore + 1)

    pending = RECORDED.timers[#RECORDED.timers]
    pending.fn()
    check("the debounce fires hs.reload", RECORDED.reloaded == 1, tostring(RECORDED.reloaded))

    -- A delta, not a cumulative count: earlier sections leave alerts behind, so
    -- a cumulative assertion passes even when dispatch does nothing.
    local alertsBefore = #RECORDED.alerts
    -- One overwritten slot, so it has to be cleared here rather than relied on
    -- to be untouched by everything above.
    RECORDED.fallbackOpened = nil
    hs.urlevent.httpCallback("https", "one.example", {}, "https://one.example", 1)
    check(
      "a clicked link reaches the picker rather than the fallback",
      #RECORDED.alerts == alertsBefore + 1 and RECORDED.fallbackOpened == nil,
      "alerts+" .. (#RECORDED.alerts - alertsBefore)
    )

    -- An empty target list is reachable: local.browsers.targets = [] is a legal
    -- option value, and picker.lua raises on it deliberately. Forcing a nil
    -- instead would prove the fallback only for a state nix cannot produce.
    local savedTargets = browsers.targets
    browsers.targets = {}
    local raised = pcall(hs.urlevent.httpCallback, "https", "two.example", {}, "https://two.example", 1)
    browsers.targets = savedTargets
    check("a raising dispatch does not propagate out of the callback", raised)
    check(
      "the fallback opens the link instead of dropping it",
      RECORDED.fallbackOpened ~= nil and RECORDED.fallbackOpened.url == "https://two.example",
      RECORDED.fallbackOpened and RECORDED.fallbackOpened.url
    )
    check(
      "the fallback bundle needs nothing outside the stub",
      RECORDED.fallbackOpened and RECORDED.fallbackOpened.bundle == STUBFALLBACK,
      RECORDED.fallbackOpened and RECORDED.fallbackOpened.bundle
    )

    -- The whole reason the callback is registered before anything that can
    -- fail. A config that throws must still leave every clicked link reaching
    -- the fallback; registering afterwards would drop them all silently, and
    -- with a healthy config both orders look identical.
    --
    -- The throwing init is planted under the stub's own configdir, which its
    -- package.path prepend searches ahead of the build directory — so this
    -- also proves that prepend is load-bearing.
    local plantedInit = hs.configdir .. "/lua/lua/init.lua"
    local planted = io.open(plantedInit, "w")
    if planted then
      planted:write('error("deliberately broken config")\n')
      planted:close()

      local brokenFrom = #RECORDED.notified
      package.loaded["lua.init"] = nil
      hs.urlevent.httpCallback = nil
      RECORDED.fallbackOpened = nil

      local brokeLoaded = pcall(dofile, STUBLUA)
      check("a throwing config does not stop the stub", brokeLoaded)
      check("a throwing config is reported", notifiedSince("Hammerspoon config failed to load", brokenFrom))
      check("the callback survives a throwing config", type(hs.urlevent.httpCallback) == "function")

      if type(hs.urlevent.httpCallback) == "function" then
        -- Handled, not necessarily via the fallback: router and picker are
        -- separate modules, so a throwing init.lua leaves them working and the
        -- link still reaches the picker. What must not happen is the link
        -- going nowhere, which is what registering after the load would cause.
        local handledFrom = #RECORDED.alerts
        pcall(hs.urlevent.httpCallback, "https", "broken.example", {}, "https://broken.example", 1)
        check(
          "a link is still handled when the config is broken",
          #RECORDED.alerts > handledFrom or RECORDED.fallbackOpened ~= nil
        )
      end

      os.remove(plantedInit)
      package.loaded["lua.init"] = nil
      dofile(STUBLUA)
    else
      check("could plant a throwing config", false, plantedInit)
    end

    -- The ordering contract itself. The config load is pcall-wrapped, so a
    -- throwing config alone cannot distinguish registering first from
    -- registering last — only an uncaught failure between the top of the file
    -- and the registration can, and hs.ipc and the pathwatcher are both
    -- unguarded. With the callback registered first the link still routes;
    -- registered last, every click on the machine goes nowhere.
    hs.urlevent.httpCallback = nil
    _G.PATHWATCHER_RAISES = true
    local survivedWatcher = pcall(dofile, STUBLUA)
    _G.PATHWATCHER_RAISES = nil
    check("an uncaught failure aborts the stub", not survivedWatcher)
    check("the callback is registered before anything that can fail", type(hs.urlevent.httpCallback) == "function")
    package.loaded["lua.init"] = nil
    dofile(STUBLUA)

    -- Reloaded against a configdir that does not match the one compiled in, to
    -- exercise the other side of the drift branch. The check above only proves
    -- it stays quiet when the paths agree.
    local driftFrom = #RECORDED.notified
    hs.configdir = "/wrong/hammerspoon"
    local reloadedOk = pcall(dofile, STUBLUA)
    hs.configdir = STUBCFGDIR
    check("a drifted configdir still loads", reloadedOk)
    check("a drifted configdir is reported", notifiedSince("Hammerspoon config dir drift", driftFrom))
  end
end

print("init.lua, as the stub loaded it")
-- Asserted against the state the stub's own require produced. Loading it here
-- as well would make the stub's load a cache hit, and every assertion about
-- whether the stub brings the config up unfalsifiable.
local loaded = package.loaded["lua.init"] ~= nil
check("init.lua loads", loaded, tostring(RECORDED.notifiedText))

if loaded then
  local expected = { "s", "k", "i", "f", "x", "j", "m", "d", "z", "b", "v", "c" }
  local missing = {}
  for _, key in ipairs(expected) do
    if not RECORDED.binds["hyper:" .. key] then
      missing[#missing + 1] = key
    end
  end
  check("every hyper hotkey binds", #missing == 0, "missing: " .. table.concat(missing, ","))
  check("calendar is on x, since c belongs to a browser profile", RECORDED.binds["hyper:x"] ~= nil)
  check(
    "no browser target collides with an app hotkey",
    (function()
      -- The nix assertion only compares targets against each other; it cannot see
      -- this file. hs.hotkey lets the later bind win silently, and the browser
      -- keys bind last — so a collision would kill an app hotkey with no error
      -- and every key in the list above would still test as bound.
      local appKeys = { s = true, k = true, i = true, f = true, x = true, j = true, m = true, d = true, z = true }
      for _, target in ipairs(browsers.targets) do
        if appKeys[target.key] then
          return false
        end
      end
      return true
    end)()
  )
  check(
    "a hotkey into a US app leaves a way back to the layout it interrupted",
    (function()
      -- The stranding: the hotkey used to set US itself, before windowFocused
      -- ran, so the handler read US as the current layout, recorded nothing,
      -- and the next focus elsewhere had nothing to restore.
      local focusFilter
      for i = #RECORDED.filters, 1, -1 do
        local f = RECORDED.filters[i]
        if f.arg == nil and f.subscribed[hs.window.filter.windowFocused] then
          focusFilter = f
          break
        end
      end
      if not focusFilter then
        return false
      end
      local focusedHandler = focusFilter.subscribed[hs.window.filter.windowFocused]

      NOW = 5000
      SOURCE = whu.fiProg
      local notes = mkwin(401, "vault")
      local obsidian = mkapp({ notes }, { bundle = "md.obsidian", name = "Obsidian", main = notes })
      APPS["md.obsidian"] = { obsidian }
      FOCUSED = nil
      RECORDED.binds["hyper:j"]()
      local afterPress = SOURCE
      focusedHandler(notes)
      local inObsidian = SOURCE

      local chat = mkwin(402, "general")
      mkapp({ chat }, { bundle = "com.example.Mail", name = "Mail" })
      focusedHandler(chat)
      if not (afterPress == whu.fiProg and inObsidian == whu.us and SOURCE == whu.fiProg) then
        return false
      end

      -- And the other half: a hotkey into an app that is not forced still gets
      -- the layout it names when its window arrives, whatever was active.
      SOURCE = "com.apple.keylayout.Finnish"
      local channel = mkwin(403, "channel")
      local slack = mkapp({ channel }, { bundle = "com.tinyspeck.slackmacgap", name = "Slack", main = channel })
      APPS["com.tinyspeck.slackmacgap"] = { slack }
      RECORDED.binds["hyper:k"]()
      focusedHandler(channel)
      return SOURCE == whu.fiProg
    end)(),
    "SOURCE=" .. tostring(SOURCE)
  )
  check(
    "the browser keys come from the target list",
    (function()
      for _, target in ipairs(browsers.targets) do
        if not RECORDED.binds["hyper:" .. target.key] then
          return false
        end
      end
      return true
    end)()
  )
end

if failures == 0 then
  print("\nall checks passed")
  os.exit(0)
end
print("\n" .. failures .. " failed")
os.exit(1)
