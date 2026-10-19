# docker-corosync-qnetd

A container running `corosync-qnetd`, the Corosync quorum device (QDevice)
network daemon. Use it to give an even-numbered cluster, such as a two-node
Proxmox VE cluster, an external tie-breaking vote.

It is built on `ghcr.io/linuxserver/baseimage-debian:trixie` (Debian 13) and
runs two s6-supervised services:

- `corosync-qnetd` on 5403/tcp, running as the unprivileged `coroqnetd` user.
- OpenSSH on 22/tcp. Proxmox's `pvecm qdevice setup` needs root SSH access to
  the qnetd host to exchange certificates. SSH is not used after setup.

## Running

```sh
cp docker-compose.yml.example docker-compose.yml
# edit docker-compose.yml as needed
docker compose up -d --build
```

On first start the container:

- generates SSH host keys into `/etc/ssh/keys`
- creates the qnetd NSS certificate database in `/etc/corosync/qnetd/nssdb`

Both are kept in volumes and reused on later starts.

### Volumes

| Container path        | Purpose                                         |
| --------------------- | ----------------------------------------------- |
| `/etc/corosync/qnetd` | qnetd NSS database (CA and server certificates) |
| `/etc/ssh/keys`       | SSH host keys                                   |
| `/root`               | root's home, including `.ssh/authorized_keys`   |

### Ports

| Port     | Purpose                                                |
| -------- | ------------------------------------------------------ |
| 5403/tcp | qnetd, must be reachable from every cluster node        |
| 22/tcp   | SSH for `pvecm qdevice setup`, mapped to 2222 in the example |

### Environment

| Variable                 | Purpose                                                           |
| ------------------------ | ----------------------------------------------------------------- |
| `TZ`                     | Timezone                                                          |
| `COROSYNC_QNETD_OPTIONS` | Extra arguments for `corosync-qnetd` (see `man corosync-qnetd`)    |
| `AUTHORIZED_KEYS`        | Public keys allowed to SSH in as root, one per line               |

The container reports itself healthy when `corosync-qnetd-tool -s` succeeds.

## Running on a tailnet (Tailscale sidecar)

A QDevice is a good fit for Tailscale. The qnetd host can sit anywhere, such
as another site or a cheap VPS, and still reach the cluster nodes over the
tailnet. You don't have to publish ports or open firewall holes.
`docker-compose.tailscale.yml.example` runs a `tailscale/tailscale` container
and puts qnetd in its network namespace
(`network_mode: service:tailscale`):

```sh
cp docker-compose.tailscale.yml.example docker-compose.yml
docker compose up -d --build
docker compose logs tailscale   # open the login URL, unless TS_AUTHKEY is set
```

- qnetd (5403) and SSH (22) are reachable on the sidecar's tailnet IP or
  MagicDNS name, and not on the Docker host.
- Cluster nodes reach qnetd either by running Tailscale themselves or
  through a subnet router. A subnet router must **not** run on the cluster
  (for example as a VM or LXC on one of the nodes). If it did, losing that
  node would also cut the survivor off from qnetd, and the survivor would
  lose quorum, which is the failure the QDevice exists to prevent.
- The example uses kernel networking (`/dev/net/tun`,
  `TS_USERSPACE=false`). With userspace networking qnetd still works, but
  `corosync-qnetd-tool -l` shows every client as `127.0.0.1`.
- SSH listens on the standard port 22 there and doesn't clash with the host's
  sshd, so skip step 3 below.
- Tailscale state is kept in `data/tailscale/state`, so the node keeps its
  identity and IP across restarts. Disable key expiry for the machine in the
  Tailscale admin console, otherwise the QDevice drops off the tailnet when
  the key expires.

## Proxmox VE setup

1. Install the QDevice client on **every** cluster node:

   ```sh
   apt install corosync-qdevice
   ```

2. Authorise the root SSH key of the node you will run the setup from. Root
   password login is disabled, so there is no root password to type. Put the
   node's public key (`cat /root/.ssh/id_rsa.pub`) in `AUTHORIZED_KEYS` in
   `docker-compose.yml`, then recreate the container with `docker compose up -d`:

   ```yaml
   environment:
     AUTHORIZED_KEYS: |
       ssh-rsa AAAA... root@pve1
   ```

   Keys are added to `/root/.ssh/authorized_keys` on every start if they are
   missing. Keys already in the file are kept, so taking a key out of the
   variable doesn't revoke it. To revoke a key, edit
   `data/root/.ssh/authorized_keys` as well.

   Check it works before running the setup:
   `ssh -p 2222 root@192.0.2.10 true` should return without asking for a password.

3. `pvecm` always connects on port 22. If SSH is mapped to 2222 as in the
   default example (not needed with the Tailscale example), add this to
   `/root/.ssh/config` on the node you run the setup from (replace the
   address with your container host):

   ```
   Host 192.0.2.10
       Port 2222
   ```

4. Run the setup from that node:

   ```sh
   pvecm qdevice setup 192.0.2.10   # or the tailnet IP
   pvecm status   # should now list a Qdevice vote
   ```

Once setup is done you can remove the SSH port mapping if you like. qnetd only
needs 5403/tcp.

## Upgrading from the bookworm image

The volume paths haven't changed, so existing data is reused. On start, the
NSS database is given the same ownership as a Debian package install
(`root:coroqnetd`, group-readable) so the unprivileged daemon can read it.
Your existing certificates are kept, so the cluster doesn't need to be set
up again.
