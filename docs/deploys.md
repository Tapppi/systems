# Deployment ownership

This public repository supplies modules and buildable examples. A composing repository owns actual host
names, access policy, disk identifiers, deployment provenance, activation records and operational wrappers.
Build the public examples with the commands in [README](../README.md); building activates nothing.

A private consumer pins a reachable immutable systems commit, follows its main and fresh-tool input tracks,
and imports public modules into native host definitions. Its deployment procedure must verify a clean,
recoverable candidate and the target's current provenance before activation. Moving an existing host across
repository histories requires an explicit per-host handover; a foreign revision is not ordinary ancestry.

Keep working recovery media and prior repository revisions until owner-led activation and rollback checks
pass. Public examples carry no real SSH access grants and must not be used to overwrite a fleet host.

## Isolated test guests

Activation and rollback inside an isolated test VM are authorized development checks for Darwin and Linux.
Real-host activation requires explicit authorization; Darwin activation on the real workstation remains an
owner step. A VM used as a production host, or the existing build VM, is not a disposable test target.
Build success and guest boot/activation success are separate claims.

Actual guest setups belong to M2/M3. The test boundary must identify a disposable guest and its disks,
keep activation inside it, and prevent writable host mounts or real fleet credentials from turning a guest
test into a host change. A sandbox can request a narrowly scoped host-side VM operation; it must not acquire
an unrestricted host shell or assume a Linux development guest can provide macOS virtualization.

[Lima supports experimental macOS guests](https://lima-vm.io/docs/usage/guests/macos/) from version 2.1 on ARM
macOS hosts running the same or a newer OS than the guest. Its macOS guests do not provide automatic port
forwarding or general passwordless sudo; plain mode disables host directory mounts.
The [VZ driver](https://lima-vm.io/docs/config/vmtype/vz/) uses Apple's Virtualization framework and requires
matching guest/host CPU architecture.
[Apple's macOS VM sample](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon)
demonstrates the Apple Silicon host and restore-image boundary. These capabilities do not establish a tested
repository guest setup.

The current [activation guard](../.claude/hooks/deploy-guard.sh) matches command text and cannot distinguish
guest activation from host activation. It must not be bypassed. M2's test setup needs a guest-bound launcher
and guard fixtures proving isolation and continued denial of real-host activation. This is engineering work
to implement the authorized test boundary, not another approval requirement for isolated guest activation.
