# NixOS Homelab Infrastructure Architecture Plan

## TL;DR — Strategy Overview

### Virtualisation & Container Strategy

- **Incus is the sole virtualisation platform** for all containers and VMs across all NixOS hosts.
  - LXC system containers (running NixOS inside) are the primary workload type. Services run natively via NixOS configuration inside the container — no OCI layer needed for simple services.
  - When a workload only exists as a Docker/OCI image (e.g., Immich, Grafana), it runs via Podman inside an Incus NixOS LXC container, using `oci-containers` NixOS module for declarative systemd management. This also covers docker-compose stacks.
  - Incus VMs are used when a full kernel is needed: GPU passthrough, Windows, appliance OSes (Home Assistant OS), or kernel-level isolation.
  - Incus native OCI (`--oci`) support is monitored for maturity but not relied on yet.
- **Devcontainers** run on OrbStack on the work MacBook (macOS) and on Incus NixOS LXC containers on NixOS hosts. Further devcontainer strategy to be designed separately.

### Workload Management

- Persistent Incus workloads (instances, profiles, networks, storage) are managed declaratively through **Terraform/OpenTofu** or **incus-apply**, whichever proves more suitable.
  - Terraform is the safe choice (professionally familiar, mature provider). incus-apply is evaluated as a lighter alternative.
  - NixOS `virtualisation.incus.preseed` handles initial cluster/infrastructure bootstrap. Whether it remains as a separate config location or gets consolidated into the Terraform/incus-apply definitions is to be determined — avoid two sources of truth for the same resources.
- NixOS configurations for what runs *inside* LXC containers are managed as regular NixOS modules in the git repos and pushed into containers via `incus file push` + `nixos-rebuild` or similar automation.

### Host Management

- All server hosts run **NixOS + Incus + OpenTofu + Tailscale** with shared shell configurations and tooling.
- Hosts are fully reproducible from the private `systems` repository using **Colmena** (or NixOps4 if that proves preferable).
- The work MacBook runs **macOS + nix-darwin + OrbStack** — not NixOS, not Incus. It is a thin client that connects to the cluster over Tailscale.

### Secrets & Security

- **Each host has its own 1Password vault** as the source of truth for secrets.
- Secrets are stored on hosts with **sops-nix** for offline boot capability — hosts don't need network access to 1Password at startup.
- Bootstrapping: deployment reads the host's 1Password vault, extracts the sops age decryption key, saves it on the host. The host decrypts secrets at boot and configures itself.
- **SSH access** is restricted to specific Tailnet clients via Tailscale ACLs (tailnet firewall) with SSH key authentication only.
  - Manual/emergency intervention: spin up any machine with Tailscale, temporarily modify tailnet firewall, copy client SSH key from 1Password. This provides a strong security boundary for hive management.
  - Hosts can SSH-forward into containers rather than exposing containers directly to the tailnet.

### Network & Service Exposure

- Each host runs a **reverse proxy container** (Caddy or Traefik) for securing and exposing containerised services through the tailnet, with local Incus networking connecting to backend containers.
- **Private DNS** (AdGuard/Unbound) resolves service names for all tailnet clients.
- **Tailscale is NOT installed in every container.** Containers access the network through Incus networking → host → Tailscale. This keeps the tailnet map clean and manageable.
  - Tailscale inside a container is reserved for special cases where the containerised software needs direct tailnet access (e.g., a devcontainer that needs its own SSH identity for AI agent access).
  - If a "cloud of machines with full mesh access" is needed later, that's a separate design. For now: explicit routing through host SSH and reverse proxy.

### Repo Architecture

- **Public repo (`nix-config`)**: NixOS modules, host base configs, dotfiles, NixOS configs for LXC containers running public/open-source services, Terraform/incus-apply definitions for public workloads.
- **Private repo (`systems`)**: Colmena deployment orchestration, all sops-encrypted secrets, Terraform/incus-apply definitions for private workloads, work-related configs, host overlays with secret wiring.
- Deploy runs exclusively from the private repo. The public repo is a module library.

---

## Hardware Inventory

### bellona — Work MacBook Pro M3 Max 14"

- **Role**: Daily driver, local development, thin client to homelab cluster
- **OS**: macOS + nix-darwin + Home Manager
- **Virtualisation**: OrbStack for OCI devcontainers and local Docker workflows
- **Network**: Tailscale client, SSH into homelab hosts
- **Notable**: Will upgrade to M5 Pro 14" within ~1 month (good migration exercise for nix-darwin reproducibility)
- **Config scope**: Userspace apps, CLI tools, shared shell configs, work-specific configs, OrbStack services, work dev environments
- **NOT managed by Colmena** — uses `darwin-rebuild switch` from the private repo

### asterix — Intel N150 Mini PC (always-on, newly purchased)

- **Role**: Primary always-on server. Home network services, NAS (ZFS on multi-M.2-SSD), critical infrastructure
- **OS**: NixOS (headless)
- **Virtualisation**: Incus (cluster bootstrap node — most reliable hardware)
- **Storage**: ZFS pool across multiple M.2 SSDs. Incus uses ZFS storage backend for containers/VMs. ZFS replication for data safety.
- **Key workloads**: DNS (AdGuard + Unbound), reverse proxy, NAS/file sharing, monitoring (Grafana + Prometheus), always-on services
- **Network**: Wired Ethernet, Tailscale, Incus bridge networking
- **Priority**: This is the most critical piece of infrastructure. Rock-solid stability and storage-level replication are paramount. Minimal unnecessary services.

### tmopro18 — MacBook Pro 15" Intel 2018 (T2 chip)

- **Role**: Transitional — currently macOS, converting to NixOS in phases
- **OS progression**:
  1. **Now**: macOS with similar config to bellona (nix-darwin, dev tools)
  2. **Phase 1**: macOS headless server (pmset sleep disable, SSH access, running services)
  3. **Phase 2**: NixOS with limited laptop capabilities — backup laptop + bursty container host (devcontainers when not in use as laptop)
  4. **Phase 3**: Always-on headless NixOS server for bursty workloads (devcontainers, database services, compute-intensive tasks)
- **Virtualisation**: Incus (cluster member, secondary)
- **Hardware notes**: T2 chip requires nixos-hardware apple-t2 module. Wi-Fi needs firmware extraction from macOS before wiping. Lid close = ignore for headless operation. AMD dGPU (15" model) can be powered off in headless mode.
- **Key workloads**: Devcontainers, burst compute, database services, overflow from asterix

### obelix — Gaming PC (dual-boot NixOS + Windows)

- **Role**: Sometimes-on power host for demanding workloads and GPU access
- **OS**: NixOS (primary) + Windows (dual-boot for gaming/specific apps)
- **Virtualisation**: Incus (cluster member, on-demand)
- **Hardware notes**: NVIDIA GPU. NixOS and Windows stay in same VLAN (established decision from previous network planning).
- **Key workloads**: GPU-accelerated compute, gaming containers/VMs with GPU passthrough (experimental), heavy build jobs, AI/ML workloads
- **Power**: Only on when needed. Not always-on. Incus cluster handles member going offline gracefully.

### cacofonix — Raspberry Pi 2 Model B

- **Role**: Bedroom TV media player
- **OS**: LibreELEC or similar Kodi distribution (not NixOS — Pi 2 is ARMv7, limited NixOS support)
- **NOT part of Incus cluster** — standalone appliance
- **Network**: Tailscale for remote management if needed, otherwise local network only

### geriatrix — Raspberry Pi 2 Model B

- **Role**: TBD — monitoring display, environmental sensors, or other lightweight service
- **OS**: DietPi or Raspbian (not NixOS — same ARMv7 limitation as cacofonix)
- **NOT part of Incus cluster** — standalone appliance
- **Potential uses**: Network monitoring dashboard, Pi-hole backup, sensor data collection

---

## Incus Cluster Topology

```
Incus Cluster (3 members, Cowsql distributed database)
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  asterix (bootstrap, always-on)                         │
│  ├── dns-stack          LXC NixOS — AdGuard + Unbound   │
│  ├── reverse-proxy      LXC NixOS — Caddy               │
│  ├── monitoring         LXC NixOS — Grafana + Prometheus │
│  ├── nas-services       LXC NixOS — Samba/NFS + ZFS     │
│  └── immich             LXC NixOS — Podman + OCI images  │
│                                                         │
│  tmopro18 (secondary, bursty workloads)                 │
│  ├── dev-project-a      LXC NixOS — devcontainer         │
│  ├── dev-project-b      LXC NixOS — devcontainer         │
│  └── postgres           LXC NixOS — database services    │
│                                                         │
│  obelix (on-demand, GPU workloads)                      │
│  ├── gpu-compute        LXC NixOS — CUDA/ML workloads    │
│  ├── gaming-vm          VM — GPU passthrough              │
│  └── build-runner       LXC NixOS — CI/build cache        │
│                                                         │
└─────────────────────────────────────────────────────────┘

NOT in cluster:
  bellona (macOS) — Tailscale client, OrbStack for local dev
  cacofonix (Pi 2) — Kodi standalone
  geriatrix (Pi 2) — TBD standalone
```

Cluster quorum requires 3 database members. asterix is always on. tmopro18 is expected to be on most of the time (phases 2-3). obelix is sometimes-on — the cluster tolerates one member being offline. If obelix is frequently off, consider running with asterix + tmopro18 as voters and obelix as a non-voter spare.

---

## Network Architecture

```
Internet
  │
  ▼
ISP Router / Fiber Modem
  │
  ▼
Home Router (Google Wifi → eventually OpenWRT NanoPi)
  │
  ├── VLAN 10: Management (asterix, tmopro18, obelix mgmt)
  ├── VLAN 20: Trusted devices (bellona, phones, laptops)
  ├── VLAN 30: IoT (Hue, Chromecast, cacofonix, geriatrix)
  └── VLAN 40: Homelab VMs/Containers (Incus bridge networks)
  │
  ▼
Tailscale overlay (mesh VPN across all managed devices)
  │
  ├── bellona ── SSH ──→ asterix, tmopro18, obelix
  │              ├── via SSH forwarding ──→ containers on those hosts
  │              └── via reverse proxy ──→ web services (Grafana, Immich, etc.)
  │
  └── All tailnet clients ── DNS ──→ asterix dns-stack container
                             ── HTTPS ──→ asterix reverse-proxy container
                                          └── proxies to backend containers via Incus network
```

### Service exposure model

```
Tailnet client (bellona, phone, etc.)
  │
  │  HTTPS request: immich.home.arpa
  │
  ▼
Private DNS (AdGuard on asterix) resolves to asterix Tailscale IP
  │
  ▼
Reverse proxy container on asterix (Caddy)
  │  TLS termination, auth if needed
  │
  ▼
Incus bridge network (incusbr0, 10.10.10.x)
  │
  ▼
immich container (10.10.10.5:3001)
```

Containers do NOT have Tailscale. They communicate via Incus networking only. The host's Tailscale + reverse proxy is the single ingress point. Outbound internet from containers goes through Incus NAT → host → router.

---

## Repo Structure

### PUBLIC: `nix-config` (GitHub public)

```
nix-config/
├── flake.nix                          # Exports all modules + standalone nixosConfigurations
│
├── modules/                           # Reusable NixOS modules (host-level)
│   ├── base.nix                       # SSH hardening, firewall, locale, nix settings, common pkgs
│   ├── tailscale.nix                  # Tailscale (authKeyFile = mkDefault null for graceful degradation)
│   ├── incus-host.nix                 # Incus daemon + nftables + firewall rules for bridge
│   ├── incus-cluster.nix              # Cluster membership config (join tokens via secrets)
│   ├── desktop.nix                    # Optional GUI: XFCE, DM not started at boot, systemctl toggle
│   ├── power-headless.nix             # Lid switch ignore, sleep disable, TLP (laptop servers)
│   ├── monitoring-host.nix            # Node exporter on host for Prometheus scraping
│   ├── zfs.nix                        # ZFS pool management, scrub schedules, snapshot policies
│   └── nvidia.nix                     # NVIDIA driver setup for GPU hosts
│
├── containers/                        # NixOS configs for LXC system containers
│   ├── dns-stack/
│   │   └── configuration.nix          # AdGuard Home + Unbound, running natively in NixOS
│   ├── reverse-proxy/
│   │   └── configuration.nix          # Caddy with automatic TLS for tailnet services
│   ├── monitoring/
│   │   └── configuration.nix          # Grafana + Prometheus + Loki, running natively
│   ├── immich/
│   │   └── configuration.nix          # NixOS + Podman for Immich OCI stack (docker-compose)
│   └── base-container.nix             # Shared NixOS config for all containers (common pkgs, users)
│
├── incus/                             # Incus infrastructure-as-code (public workloads)
│   ├── profiles/
│   │   ├── nixos-service.yaml         # Profile: NixOS LXC service container defaults
│   │   ├── nixos-dev.yaml             # Profile: NixOS LXC devcontainer defaults
│   │   └── vm-default.yaml            # Profile: VM defaults
│   ├── instances/
│   │   ├── dns-stack.yaml             # Instance definition for DNS
│   │   ├── reverse-proxy.yaml         # Instance definition for reverse proxy
│   │   └── monitoring.yaml            # Instance definition for monitoring stack
│   └── terraform/                     # Alternative: Terraform/OpenTofu definitions
│       ├── main.tf
│       ├── profiles.tf
│       └── public-instances.tf
│
├── dotfiles/                          # Home Manager modules (cross-platform)
│   ├── default.nix                    # Imports all below
│   ├── shell.nix                      # Zsh/bash config, aliases, prompt
│   ├── git.nix                        # Git config (no email/tokens — set via per-host secrets)
│   ├── editor.nix                     # Neovim configuration
│   ├── tmux.nix                       # Tmux configuration
│   └── ssh-client.nix                 # SSH client config (match blocks, multiplexing)
│
├── hosts/                             # Host base configs (hardware + service selection)
│   ├── asterix/
│   │   ├── default.nix                # Imports: base, incus-host, incus-cluster, zfs, power-headless
│   │   └── hardware-configuration.nix
│   ├── tmopro18/
│   │   ├── default.nix                # Imports: base, incus-host, incus-cluster, power-headless
│   │   └── hardware-configuration.nix # T2-specific (nixos-hardware apple-t2)
│   ├── obelix/
│   │   ├── default.nix                # Imports: base, incus-host, incus-cluster, nvidia, desktop
│   │   └── hardware-configuration.nix
│   └── bellona/
│       └── default.nix                # nix-darwin config (non-sensitive parts)
│
└── README.md
```

### PRIVATE: `systems` (GitHub private)

```
systems/
├── flake.nix                          # Imports nix-config, defines Colmena hive + darwin config
│
├── overlays/                          # Per-host private additions (secrets wiring + private workloads)
│   ├── asterix.nix                    # sops secrets, private service configs
│   ├── tmopro18.nix                   # sops secrets, devcontainer definitions
│   ├── obelix.nix                     # sops secrets, GPU workload configs
│   └── bellona.nix                    # nix-darwin private overlay (work apps, tokens)
│
├── containers/                        # NixOS configs for PRIVATE LXC containers
│   ├── dev-project-a/
│   │   └── configuration.nix          # Work devcontainer NixOS config
│   └── internal-service/
│       └── configuration.nix          # Company-internal service
│
├── incus/                             # Incus IaC for PRIVATE workloads
│   ├── instances/
│   │   ├── dev-project-a.yaml
│   │   └── internal-service.yaml
│   └── terraform/
│       └── private-instances.tf
│
├── secrets/
│   ├── .sops.yaml                     # Host public keys + creation rules
│   ├── asterix.yaml                   # Encrypted secrets for asterix
│   ├── tmopro18.yaml                  # Encrypted secrets for tmopro18
│   ├── obelix.yaml                    # Encrypted secrets for obelix
│   └── bellona.yaml                   # Encrypted secrets for bellona (nix-darwin)
│
├── bootstrap/                         # Host bootstrapping scripts and docs
│   ├── README.md                      # Step-by-step bootstrap procedure
│   ├── bootstrap-host.sh              # Reads 1Password vault, provisions sops key
│   └── incus-cluster-join.sh          # Joins a new host to the Incus cluster
│
├── deploy.sh                          # Wrapper: colmena apply + incus workload deploy
│
└── README.md                          # Private: full deploy instructions
```

---

## Secrets Architecture

### Per-host 1Password vaults

Each host has a dedicated 1Password vault. This provides clean access boundaries and audit trails.

```
1Password
├── Vault: asterix
│   ├── sops-age-key          # Age private key for decrypting asterix.yaml
│   ├── tailscale-authkey     # Tailscale auth key for this host
│   ├── incus-cluster-cert    # Cluster join certificate
│   ├── adguard-password      # AdGuard admin password
│   ├── grafana-admin         # Grafana admin credentials
│   └── ...
│
├── Vault: tmopro18
│   ├── sops-age-key
│   ├── tailscale-authkey
│   ├── incus-cluster-token
│   └── ...
│
├── Vault: obelix
│   ├── sops-age-key
│   ├── tailscale-authkey
│   └── ...
│
├── Vault: bellona
│   ├── sops-age-key          # For decrypting bellona.yaml on macOS
│   ├── work-github-token
│   ├── work-npm-token
│   └── ...
│
└── Vault: Shared-Homelab
    ├── incus-cluster-password # Shared cluster auth
    └── dns-upstream-keys      # Shared across DNS configs
```

### sops-nix flow

```
1Password vault (source of truth)
      │
      │  bootstrap-host.sh reads vault, extracts age key
      ▼
/etc/sops-age-key (on host, root-only, persistent)
      │
      │  sops-nix decrypts at NixOS activation (boot / nixos-rebuild switch)
      ▼
/run/secrets/<n> (tmpfs, per-service permissions)
      │
      │  NixOS services reference secret paths
      ▼
services.adguardhome.settings... = config.sops.secrets."adguard/password".path
```

### sops configuration

```yaml
# systems/secrets/.sops.yaml
keys:
  # User key (your SSH key converted to age, for editing secrets)
  - &tapani age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

  # Per-host keys (host SSH key converted to age, for decryption at boot)
  - &asterix age1aaaaaaaaaaaaaaaaaa
  - &tmopro18 age1bbbbbbbbbbbbbbbbbb
  - &obelix age1cccccccccccccccccc

creation_rules:
  # Each host's secrets are only decryptable by that host + you
  - path_regex: secrets/asterix\.yaml$
    key_groups:
      - age: [*tapani, *asterix]

  - path_regex: secrets/tmopro18\.yaml$
    key_groups:
      - age: [*tapani, *tmopro18]

  - path_regex: secrets/obelix\.yaml$
    key_groups:
      - age: [*tapani, *obelix]

  - path_regex: secrets/bellona\.yaml$
    key_groups:
      - age: [*tapani]  # macOS uses user age key directly
```

---

## SSH & Access Security Model

### Tailnet firewall (Tailscale ACLs)

```jsonc
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:admin"],           // bellona, emergency devices
      "dst": ["tag:server:22"]         // asterix, tmopro18, obelix SSH
    },
    {
      "action": "accept",
      "src": ["tag:client"],           // phones, tablets, other devices
      "dst": ["tag:server:443"]        // HTTPS only (reverse proxy)
    },
    {
      "action": "accept",
      "src": ["tag:client"],
      "dst": ["tag:server:53"]         // DNS
    }
  ]
}
```

### SSH access patterns

```
Normal operation:
  bellona (tag:admin) ──SSH──→ asterix (port 22)
  bellona ──SSH -J asterix──→ containers (via SSH forwarding / incus exec)

Emergency access:
  1. Spin up any machine (VPS, friend's laptop, phone with Termius)
  2. Install Tailscale, join tailnet
  3. Temporarily add device to tag:admin in Tailscale ACLs
  4. Copy SSH private key from 1Password
  5. SSH into affected host
  6. Fix issue
  7. Remove temporary device from tag:admin, revoke Tailscale device

Container access (no direct SSH to containers):
  bellona ──SSH──→ asterix ──incus exec──→ dns-stack container
  bellona ──SSH -L 3000:10.10.10.5:3000──→ asterix  (port forward to Grafana)
  bellona ──HTTPS──→ grafana.home.arpa ──reverse proxy──→ monitoring container
```

---

## Bootstrapping a New Host

### Procedure

```bash
# 1. Install base NixOS from public repo (standalone config, no secrets)
sudo nixos-install --flake github:tapani/nix-config#asterix

# 2. First boot — system works but services needing secrets are degraded

# 3. Create 1Password vault for this host (if not already done)

# 4. Run bootstrap script from private repo (on a trusted machine)
cd ~/systems
./bootstrap/bootstrap-host.sh asterix
# Script: reads 1Password vault → extracts age key → writes to host →
#         copies sops secrets → runs initial Colmena deployment

# 5. Colmena deploys full config with secrets
colmena apply --on asterix

# 6. Configure Tailscale ACLs for the new host

# 7. If Incus cluster member: join the cluster
./bootstrap/incus-cluster-join.sh asterix

# 8. Deploy Incus workloads
cd incus && terraform apply  # or incus-apply
```

---

## Workload Definition Examples

### Incus instance YAML

```yaml
# nix-config/incus/instances/dns-stack.yaml
name: dns-stack
image: images:nixos/25.11
type: container
profiles:
  - nixos-service
config:
  limits.cpu: "1"
  limits.memory: 512MiB
  security.nesting: "false"
  boot.autostart: "true"
  boot.autostart.priority: "10"
devices:
  eth0:
    type: nic
    network: incusbr0
    ipv4.address: 10.10.10.2
```

### NixOS config inside the container

```nix
# nix-config/containers/dns-stack/configuration.nix
{ config, pkgs, ... }: {
  imports = [ ../base-container.nix ];
  networking.hostName = "dns-stack";

  services.adguardhome = {
    enable = true;
    settings.dns.upstream_dns = [ "127.0.0.1:5335" ];
  };

  services.unbound = {
    enable = true;
    settings.server.port = 5335;
  };

  networking.firewall.allowedTCPPorts = [ 53 3000 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
  system.stateVersion = "25.11";
}
```

### Private workload (in systems repo)

```yaml
# systems/incus/instances/dev-project-a.yaml
name: dev-project-a
image: images:nixos/25.11
type: container
profiles:
  - nixos-dev
config:
  limits.cpu: "4"
  limits.memory: 8GiB
  security.nesting: "true"
  boot.autostart: "false"
target: tmopro18
```

---

## Deployment Workflow

```bash
# Deploy host changes
colmena apply --on asterix          # single host
colmena apply                       # all hosts

# Deploy Incus workloads
cd incus && terraform apply          # or: incus-apply apply

# Push NixOS configs into containers
incus file push -r containers/dns-stack/ dns-stack/etc/nixos/
incus exec dns-stack -- nixos-rebuild switch

# Deploy macOS config
darwin-rebuild switch --flake ~/systems#bellona

# Edit secrets
sops secrets/asterix.yaml
colmena apply --on asterix
```

---

## Implementation Phases

### Phase 1: Foundation (asterix)
1. Set up `nix-config` public repo with base modules and dotfiles
2. Create `hosts/asterix/` with NixOS config for N150 mini PC (ZFS, headless)
3. Install NixOS on asterix, verify standalone rebuild
4. Create `systems` private repo with Colmena and sops-nix
5. Deploy first Incus workload: dns-stack

### Phase 2: bellona (macOS)
6. Add nix-darwin config for bellona
7. Set up Home Manager for cross-platform dotfiles
8. Verify darwin-rebuild from private repo

### Phase 3: tmopro18 conversion
9. Extract Wi-Fi firmware while still on macOS
10. Install NixOS with T2 support
11. Join Incus cluster as second member
12. Deploy devcontainers on tmopro18

### Phase 4: obelix + cluster completion
13. Install NixOS (dual-boot with Windows)
14. Join Incus cluster — quorum achieved
15. Test GPU passthrough for VMs

### Phase 5: Service build-out
16. Deploy all Incus workloads: monitoring, immich, reverse proxy
17. Configure private DNS and Tailscale ACLs
18. Set up ZFS backup strategy

### Phase 6: Hardening
19. Audit secrets, test host recovery from scratch
20. Document emergency access procedures
21. Test Incus cluster failover

---

## Key Design Decisions

1. **Incus as sole virtualisation platform.** One orchestration layer, one networking model, one CLI. Podman only inside LXC containers when OCI images are needed.

2. **No Kubernetes.** Three heterogeneous nodes below K8s value threshold. Incus clustering + NixOS + Colmena covers the same ground with less overhead.

3. **Per-host 1Password vaults + sops-nix.** Source of truth in 1Password, offline boot via sops. Per-host isolation — compromising one host doesn't expose others.

4. **Tailscale per-host only, not per-container.** Reverse proxy + private DNS handles service exposure. Clean tailnet, simple ACLs, single ingress per host.

5. **Public repo as module library, private repo as deployment driver.** Public repo has zero secrets. Private repo is the sole deployment source.

6. **Terraform/OpenTofu for Incus workloads.** Professionally familiar, mature. incus-apply evaluated as lighter alternative.

7. **SSH forwarding into containers, not direct container SSH.** One SSH endpoint per host. Containers via `incus exec` or port forwarding.

8. **Phased tmopro18 conversion.** macOS → headless mac → NixOS laptop → headless NixOS server. Each phase standalone-useful.

9. **Raspberry Pis outside cluster.** Pi 2 (ARMv7) lacks NixOS/Incus support. Standalone appliances.

10. **Colmena over NixOps4 (tentative).** Stateless, parallel, simple. NixOps4 evaluated if needed. Architecture supports switching.
