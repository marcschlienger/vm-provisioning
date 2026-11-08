# VM Provisioning

Incus-based provisioning for persistent VMs and one system container on a
personal Ubuntu Server 26.04 host.

**Workloads:** JupyterHub (Incus system container), Ollama + OpenWebUI (Incus
VM), persistent LaTeX workspace (Incus VM), persistent agent sandboxes (Incus
VMs with Claude Code / Codex / T3 Code).

The host setup — storage layout, Tailscale, Docker, Caddy, Nextcloud, backups —
is a separate repository, `home-server-provisioning`.

## Where this repository meets `home-server-provisioning`

The two repositories share no code or configuration. They touch at four points:

- **`/srv/incus`** — the dedicated filesystem. `home-server-provisioning`
  creates it as a logical volume; this repository uses it as the Incus
  storage-pool source.
- **Docker and Incus on one host** — Docker's forwarding policy blocks Incus
  guests. [`scripts/install-incus-docker-forwarding.sh`](./scripts/install-incus-docker-forwarding.sh)
  installs the exception.
- **Caddy to OpenWebUI** — the Caddyfile in `home-server-provisioning` proxies
  to the address of the Ollama VM that this repository creates.
- **`GIT_REPOS_ROOT`** — the host repository directory that this repository
  mounts into VMs and that the host's backups include.

## Start here

- **[`SETUP.md`](./SETUP.md)** — Incus, image builds, workspace VMs, day-to-day
  usage, troubleshooting, file layout reference.
- **[`PROJECT_REVIEW.md`](./PROJECT_REVIEW.md)** — static review, accepted
  tradeoffs, and residual verification limits.
- **[`scripts/teaching-vm.sh`](./scripts/teaching-vm.sh)** — persistent teaching
  workspace with separate public/private repositories and personal TEXMF.
- **[`config.env`](./config.env)** — tracked defaults (resource sizes, image
  names, repository roots, and teaching-workspace inputs).
- **[`MIGRATION.md`](./MIGRATION.md)** — one-time steps when moving from an
  earlier layout or tool set.
- **[`LICENSE`](./LICENSE)** — MIT License.
- **`config.env.local`** (you create it; gitignored) — local values such as the
  real dotfiles repo URL or a Jupyter Tailscale auth key. Launch and build
  scripts source it after `config.env`, so its values override the defaults.

## Getting the repository onto a host

The runbook assumes this repository is on the machine it configures. Put it
there by whichever path you prefer:

```bash
# Option A — clone from your git server (Codeberg / GitHub / GitLab / private):
cd ~/
git clone <your-URL-for-this-repo> vm-provisioning
cd vm-provisioning

# Option B — rsync from your workstation if you keep it locally:
rsync -av ~/path/to/vm-provisioning/ user@server:~/vm-provisioning/
```

The point is just "make these files available on the server." Git is the
clean path; rsync works fine if you don't want to publish this anywhere.

## Quick verification

After cloning, sanity-check the cloud-init templates locally:

```bash
shellcheck -x scripts/*.sh systemd/incus-docker-forward
./scripts/validate-cloud-init.sh
bash -n scripts/*.sh
```

All checks should pass.

On a host that runs both Docker and Incus, install the persistent bridge
forwarding integration once after installing those services:

```bash
sudo ./scripts/install-incus-docker-forwarding.sh
```

## GitHub Publishing Notes

- `config.env` contains tracked defaults only. Keep real private values in
  `config.env.local`, which is ignored by Git.
- Documentation and tracked examples use placeholders rather than real
  usernames, hostnames, domains, IP addresses, repository URLs, or auth keys.
- Preserve legal attribution in `LICENSE`; do not copy its identity into
  operational examples where it is not needed.
- The fixed VM login `admin` / `admin` is intentionally host-private on the
  Incus bridge; do not expose VM SSH publicly.
- Licensed under the MIT License. See `LICENSE`.
