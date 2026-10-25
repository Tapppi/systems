# Writable agent-skills environments

`agent-skills-setup` provisions user-owned document/browser dependencies with explicit Nix-provided uv and
Node launchers. The setup source and launchers are immutable; Python packages, JS packages, uv tools and
browser downloads stay writable. No legacy checkout, mise shim or ambient global Python supplies setup code.

```sh
nix run .#agent-skills-setup -- --help
# Explicit owner setup, when this command owns the target environment:
nix run .#agent-skills-setup
```

The default `all` action runs `venv`, `markitdown` and `node`, attempts each independent stage and returns
nonzero if any fails. Individual actions are available, for example `agent-skills-setup venv`.
This is an explicit provisioning command, not a host activation command. It downloads user-level runtimes
and packages; building it or importing its Home Manager module performs no provisioning. Host cutover must
assign one setup writer before retiring its predecessor.

## Composition and destinations

`lib.mkAgentSkillsSetup { pkgs; uv ? pkgs.uv; nodejs ? pkgs.nodejs_24; }` creates the setup package and the
`agent-skills-python` launcher. `packages.<system>.agent-skills-setup` and the matching flake app use the base
pin on aarch64-darwin, aarch64-linux and x86_64-linux. The constructor binds uv/npm to explicit paths and puts
the selected Node ahead of ambient tools for npm's interpreter. Its `uv` and `nodejs` passthru values expose
those dependencies for inspection. They do not install global executable aliases.

`homeManagerModules.agentSkills` exposes `programs.systems-agent-skills.enable`, false by default, and an
optional `package` override. Enabling it only puts both commands in `home.packages`. It adds no activation
script, identity, state version, browser service or network operation. Consumers own activation and
whether to run setup. To select different inputs:

```nix
programs.systems-agent-skills = {
  enable = true;
  package = systems.lib.mkAgentSkillsSetup { inherit pkgs uv nodejs; };
};
```

| Destination | Owner and behavior |
| --- | --- |
| `$HOME/.local/share/agent-skills/venv` | Writable venv bound to uv-managed CPython 3.14 |
| `$HOME/.local/share/agent-skills/node` | Writable npm prefix, used with `NODE_PATH=<prefix>/node_modules` |
| uv's Python/tool directories | uv owns CPython, markitdown and its CLI link; normal uv location overrides apply |
| Playwright browser cache | Playwright provisions Chromium; its normal browser-path override applies |

The fixed skill-environment paths preserve existing consumers. HOME must be absolute, without trailing or
repeated slashes or `.`/`..` segments. These spellings are rejected before filesystem writes; symlinks are not
resolved to accept them. Normal platform ancestor aliases such as `/tmp` remain usable. Setup refuses a
symlinked or non-directory HOME/skill destination, and refuses root or a HOME under `/nix/store`. A directory
lock under the skill root prevents concurrent setup commands; an interrupted lock requires explicit recovery. Help writes nothing.

## Python, tools and updates

A runnable Python 3.14 venv whose `pyvenv.cfg` home points into `uv python dir` is retained in place.
The [Python dependency list](../setup/agent-skills/python-requirements.txt) is installed with `uv pip install`,
which leaves additional packages present and does not request upgrades. uv provisions its managed Python
with `--no-bin`, so setup does not add a Python executable ahead of the host's global selection.

`agent-skills-python script.py` executes this venv's Python after checking its binding and recovery state.
This is the owned interface for ad-hoc scripts importing `openpyxl`; it avoids writing packages into whichever
global `python3` happens to resolve, including immutable Nix Python. It does not rename `python3`, automatically
provision a missing environment or migrate existing script callers. A global-Python cutover must replace such
callers/writers explicitly.

`markitdown[pptx,xlsx,xls]` is a separate uv tool bound to the same Python minor. Repeated setup does not request
an upgrade. Its explicit update command is `uv tool upgrade markitdown` using the selected uv installation.
The [Node package list](../setup/agent-skills/node-packages.txt) uses `@latest` and therefore refreshes those
packages on each run. npm uses the local prefix with lifecycle scripts, audit and funding calls disabled;
additional declared dependencies remain in its package manifest. Unrecorded/extraneous node_modules content
is not a supported preservation contract.

These mutable dependency selections are not locked by `flake.lock`. Record resolved packages when validating
an update; pinned uv/Node versions alone do not reproduce a future npm/PyPI resolution. Updating launcher
inputs and updating mutable skill libraries are separate operations. This command does not provide a runtime
release-age policy or transfer the host's other Python/JS installations.

## Rebuild recovery

A missing, broken, wrong-minor or non-uv-bound venv is rebuilt. Existing package names are collected with uv
freeze and supplemented from installed dist-info names, including when the interpreter cannot run. A rebuild
reinstalls those names alongside the declared requirements. This preserves availability of ordinary extra
packages, not their exact old versions, editable-source locations or arbitrary direct-URL identity; the package sources must still
be reachable. A valid environment is not recreated merely because launcher ownership changes.

The old venv stays at `venv.old` until dependencies, extras and Chromium provisioning succeed. On rebuild
failure, the incomplete replacement is removed and the original directory restored. A failed first setup
removes only its newly created incomplete venv. A pre-existing `venv.old` is never automatically deleted:
setup refuses that venv stage. Other independent stages in `all` can still run, and the command reports failure.
Changes made inside an already valid venv or Node prefix are not transactional snapshots.

For an interrupted rebuild, first confirm no setup process remains. Preserve any desired files from the
incomplete venv, move that directory aside, and move `venv.old` back to `venv`. If the replacement is complete
and desired, move the recovery copy to a separate backup location. Remove the empty `.setup-lock` with `rmdir`
only after confirming no setup is active, then retry. Setup does not guess which surviving environment to keep.

## Browser and document prerequisites

The venv stage runs `playwright install chromium`; successful package installation alone is insufficient.
Linux hosts additionally need Playwright's platform libraries and an appropriate browser execution environment.
The installer does not run `install-deps`, sudo, a system package manager or host activation. Keep those host
prerequisites under their declared platform owner. Document tools such as Poppler, pandoc, qpdf and tesseract
are also separately owned; installing Python wrappers does not supply their executables.

The [native integration runner](../tests/agent-skills/integration.py) requires explicit paths to the built
package, its uv/Node dependencies and an installed `pdftoppm`, plus a new disposable output directory. It sets
an explicit minimal environment, confines downloads/state to that directory, runs initial/repeat/recovery
setup, retains local Python/JS extras, generates XLSX/PDF/DOCX, renders the PDF, launches Chromium on local
synthetic content, and records resolved dependencies and logs. It neither reads the live skill environment
nor activates a host. Do not point the output at an existing directory.

`checks.<system>.agent-skills-setup` exercises the packaged source with offline process doubles, validates
opt-in Home Manager composition and verifies that actual package help has no writes. These checks build on
all three supported architectures. A native integration run establishes only the runtime/platform actually
used; Linux build/mock checks do not prove Linux browser provisioning. Neither test establishes disposable-VM
boot, host/Home Manager activation, offline activation, repeated activation or rollback of a host.
