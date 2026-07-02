# fotografm/nixos-x11-4

NixOS config for x11-4 Incus hypervisor (192.168.8.50), self-managed.

x11-5 has its own separate repo: [fotografm/nixos-x11-5](https://github.com/fotografm/nixos-x11-5)

---

## How this works

**`/etc/nixos/` on x11-4 is the single source of truth.** This directory is
itself a git repo. Changes are made directly on the machine, tested with
`nixos-rebuild`, committed, then pushed to GitHub from the machine itself.

There is no copy of this config on pavi-mint — GitHub is purely a backup and
history store. You do not need pavi-mint to rebuild x11-4.

```
x11-4: /etc/nixos/   ← edit files here, source of truth
      │
      │  git push (from x11-4)
      ▼
github.com/fotografm/nixos-x11-4   ← GitHub backup / history
```

---

## How to make a config change

1. SSH into x11-4 (root login is disabled - use `user` + sudo):

```
ssh user@192.168.8.50
```

2. Edit the config:

```
vim /etc/nixos/configuration.nix
```

3. Test the change (applies but does not set as default boot generation):

```
nixos-rebuild test --flake /etc/nixos#x11-4
```

4. Apply permanently once happy:

```
nixos-rebuild switch --flake /etc/nixos#x11-4
```

5. Commit and push to GitHub:

```
git -C /etc/nixos add -p
git -C /etc/nixos commit -m "describe your change"
git -C /etc/nixos push
```

---

## How to roll back

Select a previous generation at the systemd-boot menu at boot, or:

```
nixos-rebuild switch --rollback
```

---

## Password storage

`user` has a password-based SSH fallback (`PasswordAuthentication = true`) for
logging in from a machine that doesn't have this host's key trusted yet.

The password hash is **never committed to this repo** (it's public) - it lives
only on the machine, at `/etc/nixos/secrets/user-password-hash`, which is
`.gitignore`'d and root-only readable (`chmod 600`). `configuration.nix` only
ever references the file *path* via `hashedPasswordFile`.

To set or rotate the password:

```
mkpasswd -m sha-512 | sudo tee /etc/nixos/secrets/user-password-hash > /dev/null
sudo chmod 600 /etc/nixos/secrets/user-password-hash
sudo nixos-rebuild switch --flake /etc/nixos#x11-4
```

`root` has no password at all (`hashedPassword = "!"`) and `PermitRootLogin =
"no"` - root cannot log in over SSH under any circumstances. Use `user` + sudo
(passwordless for the `wheel` group) instead.

This requires `users.mutableUsers = false;`. Without it, NixOS does not
enforce a declared password onto an account that already has one set outside
of config (e.g. from the installer) - it's only applied on first creation.

---

## Repository layout

```
nixos-x11-4/  (= /etc/nixos/ on x11-4)
├── flake.nix               # standalone flake — defines nixosConfigurations.x11-4
├── flake.lock              # pins nixpkgs version
├── configuration.nix       # all host config: networking, incus, user, SSH, packages
└── hardware-configuration.nix  # generated at install time — do not edit
```

All config is in `configuration.nix` — there is no split into modules. This is
intentional for a self-managed machine: one file is easier to read and edit
directly on the machine.

---

## Host details

| Property | Value |
|---|---|
| Hostname | `x11-4` |
| IP | `192.168.8.50` |
| Role | Incus hypervisor (containers + VMs) |
| SSH | `ssh user@192.168.8.50` |
| Incus UI | `https://192.168.8.50:8443` |
| NixOS | 26.05 (Yarara) |
| Incus | feature release |

## Hardware

| Component | Detail |
|---|---|
| Disk | SSD at `/dev/sda` |
| `/dev/sda1` | EFI boot |
| `/dev/sda2` | ext4 — NixOS root + /nix/store |
| `/dev/sda3` | btrfs — Incus storage pool (Incus-managed) |

---

## End-to-end install procedure (fresh machine)

### 1 — Boot NixOS installer

Boot from a NixOS 26.05 minimal ISO. Enable SSH in the installer:

```
sudo -i
passwd
systemctl start sshd
ip -o -4 addr show   # note the DHCP IP
```

Then from pavi-mint: `ssh root@<installer-ip>`

### 2 — Check the NIC name

```
ip -o link
```

If the physical ethernet is not `eno1`, edit `configuration.nix` after install
and change `eno1` in the bridge config to the real name.

### 3 — Wipe and partition the SSD

```
lsblk -o NAME,SIZE,TYPE,FSTYPE    # confirm /dev/sda is the right disk
wipefs -a /dev/sda
sgdisk --zap-all /dev/sda
```

```
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 1GiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart primary 1GiB 61GiB
parted /dev/sda -- mkpart primary 61GiB 100%
```

### 4 — Format and mount

```
mkfs.fat -F32 -n BOOT /dev/sda1
mkfs.ext4 -L nixos /dev/sda2
# /dev/sda3 left unformatted — Incus formats it as btrfs on first boot
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount /dev/disk/by-label/BOOT /mnt/boot
```

### 5 — Clone the repo and install

```
nix-shell -p git
git clone https://github.com/fotografm/nixos-x11-4.git /tmp/nixos-x11-4
```

Copy the generated hardware config into the clone:

```
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos-x11-4/hardware-configuration.nix
```

Install:

```
nixos-install --flake /tmp/nixos-x11-4#x11-4 --no-root-passwd
umount -R /mnt && reboot
```

### 6 — Post-install: make /etc/nixos a git repo

After booting into the new system, set up `/etc/nixos/` as a proper git repo
pointing at GitHub so future changes can be pushed. Root login is disabled, so
SSH in as `user` and get a root shell via sudo for these root-owned files:

```
ssh user@192.168.8.50
sudo -i
cd /etc/nixos
git init -b main
git remote add origin git@github.com:fotografm/nixos-x11-4.git
```

Generate and register an SSH deploy key:

```
ssh-keygen -t ed25519 -C "x11-4-nixos" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Add the printed key as a **write-access** deploy key in GitHub:
Settings → Deploy keys on `fotografm/nixos-x11-4` → Add deploy key (tick
"Allow write access").

```
ssh-keyscan github.com >> ~/.ssh/known_hosts
git add -A && git commit -m "initial config" && git push -u origin main
```

---

## Using Incus

### Launch a Debian container

```
incus launch images:debian/12 mycontainer
```

Set a static LAN IP inside the container:

```
incus exec mycontainer -- bash -c 'cat > /etc/systemd/network/eth0.network <<EOF
[Match]
Name=eth0

[Network]
Address=192.168.8.126/24
Gateway=192.168.8.1
DNS=192.168.8.70
DNS=1.1.1.1
EOF'
incus restart mycontainer
```

### Launch a VM

```
incus launch images:debian/12 myvm --vm
```

### Snapshots

```
incus snapshot create mycontainer snap1
incus snapshot restore mycontainer snap1
incus copy mycontainer mycontainer-clone
```

### Incus web UI

Browse to `https://192.168.8.50:8443`. Add a trust token from x11-4:

```
incus config trust add --name pavi-mint
```

---

## Troubleshooting

**Lost SSH after rebuild** — select previous generation at systemd-boot menu,
or `nixos-rebuild switch --rollback`.

**Incus preseed didn't apply** — reset the daemon state (destroys all containers):

```
systemctl stop incus.service incus.socket
rm -rf /var/lib/incus/database
systemctl start incus.service
```

**Container can't reach LAN** — verify `br0` is up (`ip -br link show br0`),
and the container is bridged to it (`incus config show <name> --expanded | grep parent`).
