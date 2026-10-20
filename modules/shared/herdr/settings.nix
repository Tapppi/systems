{
  onboarding = false;
  update = {
    # Only the binary is immutable; agent-detection manifests remain writable.
    version_check = false;
    manifest_check = true;
  };
  ui = {
    # Symbols require Herdr >= 0.8.2.
    status_indicators = "symbols";
    show_agent_labels_on_pane_borders = true;
  };
}
