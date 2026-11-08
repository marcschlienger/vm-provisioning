# Project Review

What the static checks cover, what they cannot prove, and the tradeoffs this
repository accepts. Run the checks with:

```bash
shellcheck -x scripts/*.sh systemd/incus-docker-forward
bash -n scripts/*.sh
./scripts/validate-cloud-init.sh
```

The validator parses every cloud-init document, checks that `runcmd` items have
the types cloud-init accepts, renders each launch template with sample and
default values and scans for unresolved placeholders, and enforces the workspace
mount path and ordering contract, the agent install boundary, and the T3 Code
forward's bind range.

Properties the static checks establish or the repository maintains:

- Launch-script help paths exit successfully without requiring Incus
  (`./scripts/<name>.sh --help`).
- `incus init` precedes VirtioFS device attachment and `incus start` in both
  workspace VM scripts; the validator's mount-contract check asserts this.
- Relative links in the documentation resolve to tracked files.
- Tracked documentation and examples use placeholders rather than real
  hostnames, personal usernames, domains, IP addresses, repository URLs, or auth
  keys. The only personal name is the copyright attribution in `LICENSE`.

None of these runs live Incus image builds, VM or container launches, package
installs, or GPU passthrough. The Residual Verification Limits section lists
what that leaves unproven.

## Design Properties

The launch and build scripts implement the following:

- Workspace VMs are initialized stopped, receive their VirtioFS project device,
  and only then start. Failed attachment or first start removes the incomplete
  VM.
- LaTeX and agent launchers accept repeatable extra repository mounts. Guest
  paths are limited to the explicit workspace and TeX trees, every device is
  attached before first boot, and repeated mount arguments are verified on
  re-entry. This also exposes custom `.sty` and `.cls` repositories through
  TeX Live's standard per-user `~/texmf` tree without copying them into images.
- A small teaching wrapper keeps the common source/private/TEXMF combination
  in configuration, verifies one known TeX input with `kpsewhich`, and reduces
  normal use to one command without hiding the generic mount mechanism. A
  companion check validates those mounts and can compile one representative
  document without opening an interactive shell.
- Re-entry validates any repeated `--git` path, handles frozen VMs, waits for
  cloud-init, and reports bootstrap failures instead of silently entering an
  incomplete VM.
- The LaTeX image derives from the agents image and inherits native Claude and
  the Codex/T3 Code installer scripts. Image builds validate that stable
  prerequisite. Codex and T3 Code install once in each workspace VM's writable
  filesystem; first boot and re-entry execute every advertised CLI rather than
  merely checking that a launcher exists.
- Agent images carry no Node.js: Claude is a native package, Codex a standalone
  binary, and T3 Code a self-contained archive. Claude uses Anthropic's signed
  stable APT channel, Codex uses its supported standalone installer, and T3 Code
  uses its release installer, which checks a SHA-256 sum. Their payloads are
  intentionally excluded from published images and installed only during
  workspace first boot. T3 Code is installed for the `admin` user and its server
  runs as a system unit with a pinned listener. `scripts/t3-expose.sh` relays it
  to the host's tailnet address through a socket bound to that one address; the
  validator renders its units and checks that it refuses any address outside
  100.64.0.0/10. This replaces the previous post-TeX and first-boot repair stack
  with one installation point and one full verification.
- Image builds run the complete cloud-init validator before launching Incus, so
  YAML, `runcmd` type, and placeholder errors fail locally without creating a
  broken build instance.
- Dotfiles URLs that cannot work without guest credentials are rejected before
  launch; first boot fails clearly if cloning or installation does not finish.
- First-boot user migration now remains correct when the pre-attached VirtioFS
  mount has already created `/home/admin`.
- Jupyter and Ollama launchers wait for successful cloud-init. One-shot
  user-data is removed from Incus configuration after successful bootstrap.
- Storage selection is explicit for every launched instance; help exits with
  success; bind-mount ownership warnings inspect the directory rather than the
  unrelated invoking account; download commands now fail on HTTP errors.
- Docker's `FORWARD DROP` policy is handled by a tracked, idempotent systemd
  integration that reinstalls scoped `incusbr0` rules after boot and Docker
  restarts, including IPv6 when Docker exposes an IPv6 user chain.
- Every cloud-init `runcmd` script now enables fail-fast behavior. Download
  pipelines were replaced with checked temporary files so a failed download or
  validation cannot be hidden by the exit status of a later command.
- VM launch templates suppress cloud-init's unused authorized-key fingerprint
  module because the default `ubuntu` user has been renamed before that module
  runs and these VMs intentionally provision no authorized SSH keys.

## Accepted Tradeoffs

### VM user bootstrap is duplicated in two launch templates

Files:
- `cloud-init/launch-init.yaml.tpl`
- `cloud-init/launch-ollama.yaml.tpl`

The fixed admin user creation, sudo setup, password SSH setup, and optional
dotfiles bootstrap are duplicated between the general VM launch template and the
Ollama launch template. This is intentionally accepted because the templates
diverge after bootstrap and the duplication is small enough to keep explicit.

### Separate launch scripts stay separate

The LaTeX VM, agent VM, Ollama VM, and Jupyter container have different images,
lifecycle behavior, mounts, and access patterns. Keeping separate scripts is
simpler than hiding those differences behind one generic launcher.

### Incus uses the `dir` storage driver on dedicated ext4

The `dir` driver is less feature-rich and slower for copies and snapshots than
LVM-thin or ZFS. It is retained because it matches the ext4-based host, is easy
to inspect and recover, and the dedicated `incus-lv` still provides the
important capacity boundary from root. Daemon-wide images, backups, and logs
are redirected to custom volumes on the same pool when supported by the
installed Incus version; image and backup relocation are required.

## Possible Larger Improvements (Not Implemented)

### Investigate Incus image-layer executable behavior

The Codex standalone payload repeatedly ran in an image-build VM but segfaulted
after both derivation and fresh instance launch. Workspace payloads now avoid
image boundaries entirely, so functionality no longer depends on diagnosing this
behavior. A separate host-level investigation could still compare checksums and
extents across build and launched instances, then review the Incus version,
storage driver, backing filesystem health, and relevant upstream issues.
Changing the storage stack is outside this repository simplification.

The first comparison to make: `build-images.sh` stops the build VM with
`incus stop --force` before `incus publish`. The Incus reference describes
`--force` only as "Force the instance to stop" and does not say whether the
guest is shut down cleanly or powered off, so writes made late in the build may
not have reached the disk. Stop gracefully (or run `sync` in the guest first),
publish, and compare `sha256sum /usr/local/bin/codex` in the build VM with an
instance launched from the published image.

### Replace the fixed VM password

Prefer `incus exec` only, or provision per-host SSH public keys and disable
password authentication. This changes the access and recovery model, so it was
not folded into a lifecycle bug-fix pass.

### Pin and verify external software

Several builds intentionally track moving inputs: the Ubuntu image alias,
latest `yq`, T3 Code and Codex releases, TLJH and Ollama installers, OpenWebUI
`main`, the Claude Code stable channel, and the Nextcloud AIO `latest` image.
Pinning the remaining versions
and checksums would improve reproducibility and supply-chain control but
requires a deliberate update policy.

### Support private dotfiles securely

The current design supports anonymously readable HTTPS repositories only.
Private repositories need a one-shot credential mechanism that neither embeds a
token in Incus configuration nor leaves a private key in the guest.

### Add live Incus integration tests

A disposable test project could build minimal images and prove device ordering,
cloud-init reruns, UID/GID behavior, failure cleanup, and re-entry against a real
daemon. Static shell/YAML checks cannot prove those runtime properties.

### Define backups for VM-local state

Agent authentication/history and OpenWebUI's Docker volume live outside the
host bind-mounted repositories. If that state matters, it needs an explicit
export or backup policy instead of treating every VM as reconstructible.

## Residual Verification Limits

The static checks validate shell syntax, ShellCheck, YAML parsing, template
rendering, placeholder replacement, the agent image/first-boot install boundary,
and documentation consistency. They do not prove that:
- A fresh `incus admin init --preseed` completes on the target host without an
  existing Incus configuration.
- Incus can launch the configured images/containers on the target host.
- External installer scripts are reachable during first boot.
- TLJH, Ollama, Docker, and OpenWebUI complete successfully on live instances.
- The tracked Docker/Incus forwarding unit starts successfully and restores
  live guest internet access on the target host.
- Jupyter joins the tailnet successfully with a real `JUPYTER_TS_AUTHKEY`.
- GPU passthrough works on the target hardware.
