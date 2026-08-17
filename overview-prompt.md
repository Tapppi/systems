Okay, let's rewrite the architecture document wtih these changes, also make sure there is a TL;DR style overview sectoin in the doc which provides an overview of the host/container/oci/etc strategy  like this but more comprehensive for whole plan:
* Incus is the main platform for all virtualisation
   * except when compose is needed in which case podman in lxc nixos container is used (probably with oci-containers config  if it supports compose?)
* Persistent incus workloads are managed through preseed and/or  (terraform or incus-apply)
   * Tool depending on whether incus-apply is satisfactory or we need terraform provider (which is okay because I use it professionally).
   * Well see whether preseed is deemed unnecessary second config location compared to just centralising infra where workloads are defined.
* Server hosts (pretty much all but mac work laptop) have nixos+incus+opentofu+tailscale and shell configurations/tooling.
   * They are fully  reproducible from the systems repository with colmena (or nixops4 if I decide on that instead)
   * Each host has it's own 1password vault as source of truth for secrets, stored with sops on the hosts for offline boot
   * Bootstrapping is  to be designed and validated, but presumably deployment would read the necessary 1password vault for sops decryption key, save it on host, host decrypts secrets on boot and installs itself.
   * Each host accepts ssh connections from specific tailnet clients (tailnet firewall) with ssh key auth
      * Manual intervention on host is always possible through spinning up VPS or any machne with tailscale, temporarily modifying tailnet firewall and copying client ssh key from 1password, but this provides a good security boundary for management of the "hive".
      * Hosts can allow ssh forwarding into containers, rather than allowing direct ssh into containers
   * Each host runs a reverse proxy container for securing and exposing containerised services through tailnet, locally setup with incus networking.
      * DNS for services set through private dns server that all tailnet clients follow
   * Thus we need not have tailscale in every single container with ssh enabled, which would create a very complicated network map. Tailscale is only needed in special cases where we want the containerised software to have full tailnet access instead of limited through host (ssh + reverse proxy inbound + outbound through incus->tailnet routing?)
      * If we eventually want a "cloud of machines" with full access to everything I would design that separately, now I prefer explicit routing through host ssh and proxy
* We will investigate devcontainers more, but for now the initial plan is to have oci devcontainers that run on orbstack on work macbook and incus on nix hosts
* Devices to use in example configurations:
   * work macbook pro m3 max 14" (wil change to m5 pro 14" in a month which is a good exercise), hostname bellona
      * work config should include userspace apps, cli tools, shared shell configs, specific work configs, orbstack services, work dev configs etc.
   * always-on intel n150 (name tbd, codename asterix) based efficient minipc with multi-m.2-ssd storage for ZFS NAS and always-on services, home network services etc. This is the most critical piece of hardware, newly bought and hopefully rock solid for years to come with storage level replication etc.
   * mbpro 15" intel 2018 (name tmopro18) which right now runs macos and has similar config to work macbook and will first run as always-on mac server, but due to intel macs losing nix-darwin support and apple dropping support for the laptop soon will convert
      *  it will soon convert to a nixos host with limited laptop capabilities as a backup and bursty containers like devcontainers when not in use as laptop
      *  eventually convert to always-on headless nixos server that is for more bursty workloads requiring power e.g. devcontainers, db services, etc.
   * gaming pc dualboot nixos host (with win dual boot), name tbd codename obelix, only sometimes on for demanding workloads and nvidia gpu access
      * On this we will also test gaming containers/vms with gpu access
   * raspberry pi 2 model b running kodi for bedroom tv, name tbd codename cacofonix
   * raspberry pi 2 model b for undecided monitoring or other services, name tbd, codename geriatrix
* Repo split and containers:
   * Public repo has nix modules and configs for any incus lxc system containers running nix and incus-apply/incus-terraform configurations for public workloads 
   * Private repo has same configuration places for private workloads