# One Herdr session per tmux session. tmux must be on PATH when TMUX is set.
{ pkgs, herdr }:
pkgs.writeShellApplication {
  name = "herdr-win";
  runtimeInputs = [ herdr ];
  text = ''
    # herdr-win              attach this tmux session's herdr session locally
    # herdr-win build-host   attach it on build-host, over SSH
    #
    # --session both creates and attaches, so there is nothing to provision
    # before the first run. --remote keeps the client local and only the
    # server remote, which is what preserves clipboard and image paste.
    host="''${1:-}"

    if [ -n "''${TMUX:-}" ]; then
      session="$(tmux display-message -p '#S')"
    else
      session="''${HERDR_SESSION:-default}"
    fi

    # Detaching with prefix+q returns here rather than letting the window's
    # command exit, which would close the tmux window and take any other pane
    # in it along.
    while true; do
      if [ -n "$host" ]; then
        herdr --remote "$host" --session "$session" || true
      else
        herdr --session "$session" || true
      fi

      printf '\n[herdr-win] detached from %s%s\n' "''${host:+$host:}" "$session"
      printf 'press q to close this window, any other key to reattach: '
      read -r -n 1 key || key=q
      printf '\n'
      if [ "$key" = q ]; then
        break
      fi
    done
  '';
}
