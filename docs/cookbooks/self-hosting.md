# Cookbook: self-hosting the agent-ops runner

Run the agent-ops loop on your own hardware — a spare box, a VM on your
hypervisor (libvirt / Proxmox / VMware / Hyper-V), or bare metal. This is the
cheapest option if you already have capacity, and the only option if your model
endpoint is on a private network.

> Prereq concepts + the shared **Steps A–D** (bootstrap, register runner,
> secrets, smoke test) live in [`./README.md`](./README.md). This page only
> covers **getting the box**.

## 1. Provision the box

Any Ubuntu 22.04/24.04 (or compatible) machine with:

- 2 vCPU / 4 GB minimum (size up for `implement` — see README sizing).
- Outbound HTTPS to `github.com`, the actions runner release host, and your
  `LITELLM_BASE_URL`. **No inbound ports required** (the runner dials out).
- ~20 GB disk (more if your build caches are large).

### Option A — a VM via cloud-init (libvirt example)

This mirrors how the framework's own reference deployment is built. Create a
`user-data` and boot an Ubuntu cloud image:

```yaml
#cloud-config
hostname: agent-ops-runner
users:
  - name: runner
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [sudo]
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA...your-key...
package_update: true
packages: [git, jq, python3, curl, ca-certificates]
```

```bash
cloud-localds seed.iso user-data
qemu-img create -F qcow2 -b /path/to/noble-server-cloudimg-amd64.img -f qcow2 disk.qcow2 20G
virt-install --name agent-ops-runner --memory 4096 --vcpus 2 \
  --disk path=disk.qcow2,format=qcow2 --disk path=seed.iso,device=cdrom \
  --os-variant ubuntu24.04 --network network=default \
  --graphics none --import --noautoconsole
virsh autostart agent-ops-runner   # survive host reboots
```

Proxmox / VMware / Hyper-V: provision an equivalent Ubuntu VM however you
normally do, then continue.

### Option B — bare metal / an existing box

Just SSH in. Make a dedicated unprivileged user (`runner`) so the runner isn't
root.

## 2. Network notes

- **Behind a corporate proxy / no direct internet?** Export `HTTPS_PROXY` on the
  box for the install steps, and set the `LITELLM_NO_PROXY` secret so the
  `claude` CLI bypasses the proxy for your model gateway (or vice-versa). The
  runner service environment honours the proxy you set.
- **Private model gateway?** Self-hosting is the natural fit — the box just needs
  a route to it (same VLAN, VPN, or a tunnel). This is the case a GitHub-hosted
  runner *can't* serve.

## 3. Bring it online

Continue with **Steps A–D** in [`./README.md`](./README.md): bootstrap the box,
register the runner (label `self-hosted,agent-ops`), set the secrets, smoke-test.

## Pros / cons

| 👍 | 👎 |
|---|---|
| Free if you have capacity; reaches private model gateways; full control | You own patching, uptime, and reboot-recovery (use `virsh autostart` / a systemd-enabled service so the runner restarts) |

> Tip: register the runner as a **systemd service** (`./svc.sh install`) so a host
> reboot brings it back. A VM that doesn't auto-start its runner is the #1 cause
> of "all my CI is queued forever."
