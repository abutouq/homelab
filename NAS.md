What this machine has

┌──────────────┬──────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────┐
│     Item     │                                    Found                                     │           Good enough for a NAS?           │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ Hardware     │ Dell OptiPlex 7050, i7-7700 (8 threads), 27 GB RAM                           │ ✅ More than enough                        │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ OS           │ Ubuntu 24.04.3 LTS                                                           │ ✅                                         │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ Disk 1 (sda) │ Kingston 240 GB SSD, holds the OS, 147 GB free                               │ ⚠️ Keep it for the OS only                 │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ Disk 2 (sdb) │ WD Blue 500 GB HDD at /mnt/longhorn, 245 GB free                             │ ⚠️ Already holds Longhorn replicas and     │
│              │                                                                              │ your Immich library, and has no redundancy │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ SATA ports   │ 4 total, 2 used                                                              │ ✅ Room for 2 more drives                  │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ Network      │ Connected through a USB Wi-Fi adapter (Realtek RTL8188EUS, 2.4 GHz 802.11n). │ ❌ Biggest problem                         │
│              │  The built-in gigabit port enp0s31f6 is down, with no cable plugged in       │                                            │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ NAS software │ Samba and NFS server are not installed. mdadm, LVM, btrfs, smartmontools and │ ⚠️ Needs installing                        │
│              │  ufw are installed (ufw is active)                                           │                                            │
├──────────────┼──────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────┤
│ Existing     │ Docker running Immich, Pi-hole, Grafana/Prometheus, n8n, Uptime Kuma and     │ ℹ️ Don't replace the OS. Add the NAS on    │
│ services     │ others, plus a VPN on tun0 (10.8.0.1)                                        │ top of it                                  │
└──────────────┴──────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────┘

What you need

1. Plug in an Ethernet cable (required).
That Wi-Fi adapter will probably move only about 2–5 MB/s, which is far too slow for a NAS. Gigabit Ethernet gives you about 110 MB/s. Connect enp0s31f6 to your router, then give the machine a fixed IP, either with a DHCP reservation on the router or in netplan.

2. Add data drives (strongly recommended).
- Buy 2 matching NAS-grade HDDs, such as WD Red Plus or Seagate IronWolf, in whatever size you need, and run them as a mirror (RAID1). That way one drive can fail without losing your data.
- Before buying, check the chassis. The OptiPlex 7050 comes in MT, SFF and Micro versions with different numbers of drive bays and SATA power connectors, so you may need a SATA power splitter or a different layout.
- Leave sdb as it is: Longhorn and Immich are using it.
- Quick option with no new hardware: share a folder on sdb's 245 GB of free space. It works, but it's one aging disk with no redundancy.

3. Install the NAS software. Keep Ubuntu, since TrueNAS or OpenMediaVault would mean wiping the OS and your services.
sudo apt install samba nfs-kernel-server   # SMB for Windows/macOS/phones, NFS for Linux
# Mirror the two new disks (choose one):
sudo apt install zfsutils-linux && sudo zpool create tank mirror /dev/disk/by-id/<disk1> /dev/disk/by-id/<disk2>
#   or: sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdX /dev/sdY
I'd go with ZFS: it checks your data for silent corruption, takes snapshots and supports compression, and 27 GB of RAM is plenty for it.

4. Set up shares and users.
- Add a share in /etc/samba/smb.conf.
- Create a Samba user with sudo smbpasswd -a <user>.
- Set folder ownership and permissions.

5. Open the firewall to your LAN only, since ufw is active.
sudo ufw allow from 192.168.0.0/24 to any app Samba
sudo ufw allow from 192.168.0.0/24 to any port 2049   # only if using NFS
Don't expose SMB to the internet. For remote access, use your existing VPN (tun0).

6. Protect the data.
- Turn on smartd disk-health alerts. You already run Alertmanager, so you can send alerts there.
- Schedule ZFS snapshots and scrubs.
- Keep an off-machine backup. RAID protects against a dead drive, not against deleting files by mistake or ransomware.

Summary

Minimum: an Ethernet cable, apt install samba and one share. Recommended: an Ethernet cable, 2 NAS HDDs in a ZFS mirror, Samba, LAN-only firewall rules, SMART monitoring and a backup.

I can't run sudo here because it asks for a password, so I couldn't check disk SMART health or make any changes. Once Ethernet is connected, I can write the exact config files for you (smb.conf, the ZFS pool and ufw rules) for you to run. Do you want me to?