# shellcheck shell=bash
# Pure lexical preflight. Do not resolve symlinks to make a spelling acceptable.
# Normal platform ancestor aliases remain allowed; setup checks its owned paths separately.
agent_skills_home_spelling_valid() {
  case "${1:-}" in
    ''|/|/nix/store|/nix/store/*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  # Reject aliases instead of interpreting .. across a potentially symlinked ancestor.
  case "$1" in
    */|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
}
