# Migration

One-time steps when moving to the current layout or tool set. Each section is
independent; delete one once nothing you operate still needs it.

## Split out of `home-server-provisioning`

This repository was split from `home-server-provisioning`, which now holds only
the host and Nextcloud setup. The history of the VM material came along; commit
hashes differ. Scripts, `config.env`, and `cloud-init/` sit at the repository
root, as they did before the split.

`config.env.local` is untracked, so Git does not carry it over. Copy it from the
old checkout:

```bash
cp ~/home-server-provisioning/config.env.local ~/vm-provisioning/config.env.local
```

Existing Incus instances, images, and the installed `incus-docker-forward`
service are unaffected. The service installer now runs from here:
`sudo ./scripts/install-incus-docker-forwarding.sh`.

## Pi replaced by T3 Code in workspace VMs

New LaTeX, teaching, and agent VMs no longer install Pi. They install the T3 Code
CLI for the `admin` user and run its server as `t3code.service` on port 3773
inside the VM. `SETUP.md` section 3.5 describes reaching it from the T3 apps
(`scripts/t3-expose.sh`) and from a browser. The installer script is baked into
the agents image, so rebuild the images before creating new VMs; a VM launched
from an older image fails its first boot because
`/usr/local/sbin/install-t3-code` does not exist.

```bash
./scripts/build-images.sh
```

Existing VMs are untouched by an image rebuild. They keep Pi, and they keep
passing re-entry verification because each VM carries its own copy of
`verify-agent-clis`. To give an existing VM T3 Code, recreate it; the host
repositories mounted into it are not deleted with it, but VM-local credentials
and other files are.

## Node.js removed from agent images

Nothing installed in the agent images needs Node.js: Claude is a native package,
Codex a standalone binary, and T3 Code a self-contained archive. The agents image
no longer installs Node.js and `verify-agent-clis` no longer checks for it. A
project that needs Node.js has to bring its own.

An older `ubuntu-base` image, built before `build-base.yaml` stopped installing
Node.js, still contains it and passes it on to the images derived from it. The
full rebuild above, which starts with base, removes it. Existing VMs keep
whatever they were created with.
