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

The container reports itself healthy when `corosync-qnetd-tool -s` succeeds.

## Proxmox VE setup

1. Install the QDevice client on **every** cluster node:

   ```sh
   apt install corosync-qdevice
   ```

2. Authorise the root SSH key of the node you will run the setup from. Root
   password login is disabled, so the key has to be placed in the volume:

   ```sh
   mkdir -p data/root/.ssh
   cat id_rsa.pub >> data/root/.ssh/authorized_keys   # the node's /root/.ssh/id_rsa.pub
   sudo chown -R root:root data/root/.ssh
   sudo chmod 700 data/root/.ssh
   sudo chmod 600 data/root/.ssh/authorized_keys
   ```

3. `pvecm` always connects on port 22. If SSH is mapped to 2222 as in the
   example, add this to `/root/.ssh/config` on the node you run the setup
   from (replace the address with your container host):

   ```
   Host 192.0.2.10
       Port 2222
   ```

4. Run the setup from that node:

   ```sh
   pvecm qdevice setup 192.0.2.10
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
