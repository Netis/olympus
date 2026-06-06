# Cookbook: agent-ops runner on DigitalOcean

A Droplet is the fastest hosted option: a few dollars a month, up in a minute,
no cloud-IAM ceremony.

> Prereq concepts + the shared **Steps A–D** (bootstrap, register runner,
> secrets, smoke test) live in [`./README.md`](./README.md). This page only
> covers **getting the Droplet**.

## 1. Create the Droplet

### With `doctl`

```bash
# one-time: doctl auth init ; doctl compute ssh-key list  (note your key id/fingerprint)
doctl compute droplet create agent-ops-runner \
  --image ubuntu-24-04-x64 \
  --size s-2vcpu-4gb \
  --region nyc3 \
  --ssh-keys <your-ssh-key-fingerprint> \
  --wait

doctl compute droplet list agent-ops-runner --format Name,PublicIPv4
ssh root@<PUBLIC_IP>
```

### Or the control panel

Create → Droplets → Ubuntu 24.04 → **Basic / Regular**, `s-2vcpu-4gb`, add your
SSH key, create. Then `ssh root@<ip>`.

## 2. Sizing & cost (rough)

| Size | vCPU / RAM | ~ / month | Good for |
|---|---|---|---|
| `s-2vcpu-4gb` | 2 / 4 GB | ~$24 | triage + review |
| `s-4vcpu-8gb` | 4 / 8 GB | ~$48 | + implement with a moderate build |

To trim cost, you can **power the Droplet off when idle** (you still pay for the
disk while off, but not the vCPU) or destroy + recreate from a snapshot. For an
always-responsive loop, leave it running.

## 3. Harden a little

- The Droplet gets a public IP. Lock SSH to your IP via the **DigitalOcean Cloud
  Firewall** (inbound 22 from your address only; the runner needs **no** inbound
  otherwise — it dials out to GitHub + your model endpoint).
- Create an unprivileged `runner` user instead of using `root` for the runner
  service.

## 4. Bring it online

Continue with **Steps A–D** in [`./README.md`](./README.md): bootstrap the
Droplet, register the runner (label `self-hosted,agent-ops`), set the secrets,
smoke-test.

## Pros / cons

| 👍 | 👎 |
|---|---|
| Cheapest hosted option; trivial to create/destroy; snapshots | Public IP to firewall; you still patch the OS; egress only — can't reach a *private* model gateway unless you VPN/tunnel |
