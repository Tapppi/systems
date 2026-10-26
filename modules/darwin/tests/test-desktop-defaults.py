"""Check generated preference writes without running an activation script."""

import json
import plistlib
import shlex
import sys


EXPECTED = {
    "com.apple.finder": {
        "QuitMenuItem": True,
        "ShowExternalHardDrivesOnDesktop": True,
        "ShowHardDrivesOnDesktop": True,
        "ShowMountedServersOnDesktop": True,
        "ShowRemovableMediaOnDesktop": True,
        "AppleShowAllFiles": True,
        "ShowStatusBar": True,
        "ShowPathbar": True,
        "_FXShowPosixPathInTitle": True,
        "_FXSortFoldersFirst": True,
        "FXDefaultSearchScope": "SCcf",
        "FXEnableExtensionChangeWarning": False,
        "FXPreferredViewStyle": "Nlsv",
    },
    "-g": {
        "AppleShowAllExtensions": True,
        "com.apple.springing.enabled": True,
        "com.apple.springing.delay": 0.0,
    },
    "com.apple.dock": {
        "mouse-over-hilite-stack": True,
        "tilesize": 52,
        "mineffect": "scale",
        "minimize-to-application": False,
        "enable-spring-load-actions-on-all-items": True,
        "show-process-indicators": True,
        "launchanim": False,
        "expose-animation-duration": 0.1,
        "mru-spaces": False,
        "autohide-delay": 0.0,
        "autohide-time-modifier": 0.0,
        "autohide": True,
        "showhidden": True,
        "show-recents": False,
    },
}


def writes(script):
    # shlex keeps quoted multiline plist XML together; no shell command runs.
    tokens = shlex.split(script, comments=True)
    result = {}
    for position, token in enumerate(tokens):
        if token != "defaults":
            continue
        assert tokens[position - 6:position] == [
            "launchctl", "asuser", "$(id -u -- desktop-test)",
            "sudo", "--user=desktop-test", "--",
        ], "preference write must target the primary user through launchctl"
        verb, domain, key, xml = tokens[position + 1:position + 5]
        assert verb == "write", (verb, domain, key)
        destination = (domain, key)
        assert destination not in result, f"duplicate preference write: {destination}"
        result[destination] = plistlib.loads(xml.encode())
    return result


def flatten(values):
    return {(domain, key): value for domain, keys in values.items() for key, value in keys.items()}


def check(fixture, expected):
    assert fixture["system"] == "", "desktop preferences must not write root/system domains"
    actual = writes(fixture["user"])
    assert actual.keys() == expected.keys(), (actual.keys() ^ expected.keys())
    for key, value in expected.items():
        assert type(actual[key]) is type(value), (key, type(actual[key]), type(value))
        assert actual[key] == value, (key, actual[key], value)
    assert "killall -qu desktop-test Dock" in fixture["user"], "Dock restart must target the primary user"


def main():
    with open(sys.argv[1], encoding="utf-8") as source:
        fixtures = json.load(source)
    expected = flatten(EXPECTED)
    check(fixtures["selected"], expected)
    assert fixtures["absent"] == {"user": "", "system": ""}, "preset must be explicitly imported"
    override = expected | {
        ("com.apple.finder", "FXPreferredViewStyle"): "clmv",
        ("com.apple.dock", "tilesize"): 68,
    }
    del override[("com.apple.dock", "autohide")]
    check(fixtures["overridden"], override)
    print("PASS: 30 typed primary-user writes, opt-in isolation, native overrides and null omission")


if __name__ == "__main__":
    main()
