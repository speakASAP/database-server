# Alfares RAID1 Recovery Orchestrator Plan

## Intent Preservation Chain

- Vision: keep Alfares data available when a physical disk fails, and avoid losing database/Vault/Kubernetes backup artifacts.
- Goal Impact: restore the degraded Linux software RAID1 arrays so backup storage is mirrored rather than single-disk.
- System: Alfares host storage, Linux mdraid (`mdadm`), current second-disk backup mount `/srv/critical-backups`.
- Feature: two-member RAID1 mirror for backup storage, with clear guardrails for any later root/boot migration.
- Task: produce an implementation plan for a future root-capable agent/orchestrator. Do not execute destructive disk operations from this planning document.
- Execution Plan: verify current disk identity, select a safe replacement/new disk, add it to `/dev/md1` and `/dev/md0`, monitor rebuild, update mdadm/initramfs metadata, and validate that database and Vault/Kubernetes backup evidence remains visible.
- Coding Prompt: [MISSING: implementation prompt will be written only after a human approves the target disk and maintenance window].
- Code: no application code required. Potential host files: `/etc/mdadm/mdadm.conf`, `/etc/fstab`, initramfs metadata, possibly GRUB/EFI only if a separate boot-mirror migration is approved.
- Validation: `/proc/mdstat` must show `[UU]` for both arrays, `mdadm --detail` must show two active devices, backup jobs must still write to `/srv/critical-backups`, and `backups-microservice` must show database and Vault evidence as `success`.

## Source References

- Linux kernel md documentation: https://docs.kernel.org/admin-guide/md.html
- `mdadm(8)` manual: https://man7.org/linux/man-pages/man8/mdadm.8.html
- Local evidence collected on Alfares on 2026-06-25 around 19:29-19:35 CEST.

## Current Alfares Storage State

Live read-only findings:

```text
Host: alfares
Date: 2026-06-25T19:29:41+02:00

/dev/sda  2.7T  ST3000VX009-2AY10G  serial ZTT015X4
  /dev/sda1  vfat  UUID 11B1-CD51  mounted at /boot/efi
  /dev/sda2  ext4  UUID 4c773429-f3a2-4d65-b741-0ff8d9f895ab  mounted as /

/dev/sdb  2.7T  ST3000VX009-2AY10G  serial ZTT015D0
  /dev/sdb1  linux_raid_member  array alfares:1 -> /dev/md1
  /dev/sdb2  linux_raid_member  array alfares:0 -> /dev/md0

/dev/nvme0n1p1  ext4  UUID 0870e846-0d77-43e8-be68-7d44a138fa8d
  mounted at /mnt/docker-data
  bind-mounted to /home/ssf/Documents/Github

/dev/md0  raid1/ext4  UUID f7c1c555-e222-42bc-880e-c1772d3a5539
  mounted at /srv/critical-backups
  active member: /dev/sdb2
  missing member: slot 1
  state: clean, degraded

/dev/md1  raid1
  active member: /dev/sdb1
  missing member: slot 1
  state: clean, degraded
  not mounted
```

`/proc/mdstat` showed:

```text
md0 : active raid1 sdb2[0]
      2929031168 blocks super 1.2 [2/1] [U_]

md1 : active raid1 sdb1[0]
      1098752 blocks super 1.2 [2/1] [U_]
```

`mdadm --detail /dev/md0` showed:

```text
Raid Level : raid1
Raid Devices : 2
Total Devices : 1
State : clean, degraded
Active Devices : 1
Working Devices : 1
Number Major Minor RaidDevice State
0      8     18    0          active sync /dev/sdb2
-      0      0    1          removed
```

`mdadm --detail /dev/md1` showed the same pattern with `/dev/sdb1`.

## Critical Observations

1. The currently healthy mdraid member is `sdb`, not `sda`.
2. `sda` is not a spare disk. It is the live boot/root disk:

```text
BOOT_IMAGE=/boot/vmlinuz-6.17.0-35-generic root=UUID=4c773429-f3a2-4d65-b741-0ff8d9f895ab
/ is mounted from /dev/sda2
/boot/efi is mounted from /dev/sda1
```

3. Do not add `/dev/sda1` or `/dev/sda2` to mdraid during normal online repair. That would overwrite the live root/EFI disk or fail because it is mounted.
4. `sda` and `sdb` currently have duplicate GPT disk GUIDs and duplicate partition GUIDs:

```text
PTUUID both disks: 7202979f-5e2d-4fe1-b886-eae0f20f34e7
sda1 and sdb1 PARTUUID: 809a3f27-fe06-4050-bfb1-94a90dd7caa5
sda2 and sdb2 PARTUUID: 9bbbb515-b506-4331-ba9a-12dff87d1842
```

This duplicate GUID state can confuse boot tooling and humans. Any new replacement disk must receive unique GPT and partition GUIDs.

5. `/etc/fstab` is inconsistent with the live boot state. It contains a root entry for the md0 filesystem UUID:

```text
/dev/disk/by-uuid/f7c1c555-e222-42bc-880e-c1772d3a5539 / ext4 defaults 0 1
```

But the live kernel command line and current mount show root is `/dev/sda2`, UUID `4c773429-f3a2-4d65-b741-0ff8d9f895ab`.

Do not reboot as part of a RAID repair until this contradiction is reviewed. The existing boot path may still work because the kernel command line names `/dev/sda2`, but the fstab state is unsafe and misleading.

6. The current `/srv/critical-backups` mount is the degraded md0 filesystem on `sdb2`. It contains:

- database backup target: `/srv/critical-backups/database-server`
- root-managed Vault/Kubernetes backup target: `/srv/critical-backups/alfares-critical`

7. `alfares-critical-backup.service` and database backup jobs must not run while a destructive disk-selection step is being performed. Rebuild itself can run online, but plan execution should avoid concurrent heavy backup writes until the rebuild has started cleanly.

## What Does And Does Not Require Reboot

Adding a new member to an existing degraded mdraid RAID1 array normally does not require reboot. Linux mdraid supports adding a new device to an active array and rebuilding online.

Reboot may be required only for one of these reasons:

- the physical server does not support hot-plug/hot-swap and the disk can only be inserted/replaced while powered off;
- firmware does not expose the new disk until reboot;
- a separate boot/root RAID migration is approved and must be tested;
- the operator wants to validate bootability from each mirror member after bootloader changes.

Do not power off or unplug the current active md member `sdb` unless backup data has been copied elsewhere and a recovery plan is ready. Right now `sdb` is the only active member of `/dev/md0` and `/dev/md1`.

## Recommended Strategy

### Strategy A: Restore The Backup RAID With A Fresh Additional/Replacement Disk

Use this if a new disk appears as a new block device, for example `/dev/sdc` or a stable `/dev/disk/by-id/ata-...` path.

This is the safest path for restoring the existing degraded arrays:

- source of truth for current mdraid content: `/dev/sdb1` and `/dev/sdb2`;
- target: a new disk with no mounted filesystems and no live data;
- result: `/dev/md0` and `/dev/md1` become `[UU]`.

This does not make the live root filesystem on `/dev/sda2` mirrored. It mirrors the existing mdraid backup storage.

### Strategy B: Full Host Root/Data RAID1 Migration

Use this only if the real objective is: "the server should keep booting and running if either SATA disk dies."

This is a separate, higher-risk migration. It cannot be solved by simply adding `sda2` to `md0`, because `sda2` is the current live root filesystem. It requires a maintenance window, off-host backups, a rescue/Live environment or carefully staged root migration, bootloader work on both disks, fstab correction, and boot tests.

This document does not approve Strategy B implementation. It only flags that it is different from restoring the existing degraded backup RAID.

## Safety Gates Before Any Destructive Command

All of these gates must pass before any `sgdisk --zap-all`, `mdadm --zero-superblock`, or `mdadm --add` command:

1. Human confirms the exact physical target disk by serial number.
2. Target disk is not `/dev/sda`, not `/dev/sdb`, and not `/dev/nvme0n1`.
3. Target disk has no mounted partitions:

```bash
findmnt -S /dev/sdX || true
findmnt -S /dev/sdX1 || true
findmnt -S /dev/sdX2 || true
```

4. Target disk is not in use by LVM, mdraid, filesystem, Kubernetes local-path, Docker, or bind mounts:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL
cat /proc/mdstat
mdadm --examine /dev/sdX /dev/sdX1 /dev/sdX2 2>/dev/null || true
```

5. Current active source member is still healthy:

```bash
mdadm --detail /dev/md0
mdadm --detail /dev/md1
cat /proc/mdstat
findmnt -T /srv/critical-backups
```

6. Backup services are inactive before the initial disk preparation:

```bash
systemctl is-active alfares-critical-backup.service || true
ps -eo pid,ppid,user,stat,etime,cmd | grep -E 'alfares-critical-backup|backup-all-databases|pg_dumpall|tar --xattrs|openssl enc' | grep -v grep || true
```

7. Fresh backup evidence is already available:

```bash
python3 -m json.tool /home/ssf/Documents/Github/database-server/backup-evidence/latest.json
python3 -m json.tool /home/ssf/Documents/Github/shared/runtime-evidence/vault-backups/latest.json
```

8. A copy of current partition and mdraid metadata is saved off the target disk. Use `/root` on the server and also copy to an external location if possible:

```bash
mkdir -p /root/raid-recovery-$(date +%Y%m%dT%H%M%S)
OUT=/root/raid-recovery-YYYYMMDDTHHMMSS
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL > "$OUT/lsblk.txt"
cat /proc/mdstat > "$OUT/mdstat.txt"
mdadm --detail /dev/md0 > "$OUT/md0-detail.txt"
mdadm --detail /dev/md1 > "$OUT/md1-detail.txt"
mdadm --examine /dev/sdb1 /dev/sdb2 > "$OUT/sdb-mdadm-examine.txt"
sfdisk -d /dev/sda > "$OUT/sda.sfdisk"
sfdisk -d /dev/sdb > "$OUT/sdb.sfdisk"
blkid > "$OUT/blkid.txt"
cp -a /etc/fstab "$OUT/fstab"
cp -a /etc/mdadm/mdadm.conf "$OUT/mdadm.conf"
```

## Strategy A Detailed Execution Plan

### Phase 0: Stop Competing Backup Writes

Do not stop core applications. Only prevent backup jobs from starting during the disk preparation window.

```bash
systemctl is-active alfares-critical-backup.service || true
systemctl list-timers --all --no-pager | grep alfares-critical-backup || true
crontab -l | grep backup-all-databases || true
```

If a backup is already running, wait for it to finish. Do not kill it unless it is wedged and a human approves.

Optional during the first 10-15 minutes of repair:

```bash
systemctl stop alfares-critical-backup.service
systemctl mask --runtime alfares-critical-backup.service
```

For the user crontab database backup, prefer timing the work outside the `02:00` cron window instead of editing crontab. If the work must overlap, temporarily comment out the cron line and restore it after rebuild has started cleanly.

### Phase 1: Identify The New Target Disk

Use stable by-id names. Example only:

```bash
ls -l /dev/disk/by-id/ | grep -E 'ata-|nvme-' | grep -v part
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL
```

Expected current disks:

```text
ata-ST3000VX009-2AY10G_ZTT015X4 -> /dev/sda  live root disk, do not use
ata-ST3000VX009-2AY10G_ZTT015D0 -> /dev/sdb  active mdraid source, do not wipe
nvme-Samsung_SSD_990_PRO_1TB_S7HDNJ0Y912768Y -> /dev/nvme0n1  Git/Docker data, do not use
```

The target must be a different disk, for example:

```text
/dev/disk/by-id/ata-NEW_DISK_SERIAL -> /dev/sdX
```

Set variables only after human confirmation:

```bash
SOURCE_DISK=/dev/disk/by-id/ata-ST3000VX009-2AY10G_ZTT015D0
TARGET_DISK=/dev/disk/by-id/ata-NEW_DISK_SERIAL
SOURCE_P1="${SOURCE_DISK}-part1"
SOURCE_P2="${SOURCE_DISK}-part2"
TARGET_P1="${TARGET_DISK}-part1"
TARGET_P2="${TARGET_DISK}-part2"
```

Guardrail:

```bash
readlink -f "$SOURCE_DISK"
readlink -f "$TARGET_DISK"
test "$(readlink -f "$TARGET_DISK")" != "/dev/sda"
test "$(readlink -f "$TARGET_DISK")" != "/dev/sdb"
test "$(readlink -f "$TARGET_DISK")" != "/dev/nvme0n1"
```

### Phase 2: Prepare The Target Disk

This phase destroys all data on the selected target disk. It must not run until the target disk is confirmed.

Replicate the source partition sizes from `sdb` to the target, then randomize disk and partition GUIDs:

```bash
sgdisk --backup=/root/sdb-layout-before-raid-repair.gpt "$SOURCE_DISK"
sgdisk --zap-all "$TARGET_DISK"
sgdisk --replicate="$TARGET_DISK" "$SOURCE_DISK"
sgdisk -G "$TARGET_DISK"
```

Set target partition types to Linux RAID. This is metadata on the partition table; it does not create the md superblocks:

```bash
sgdisk --typecode=1:fd00 --typecode=2:fd00 "$TARGET_DISK"
partprobe "$TARGET_DISK"
udevadm settle
```

Confirm the target partitions exist and are not mounted:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL "$TARGET_DISK"
findmnt -S "$TARGET_P1" || true
findmnt -S "$TARGET_P2" || true
```

Remove stale mdraid signatures if this is a reused disk:

```bash
mdadm --zero-superblock --force "$TARGET_P1" "$TARGET_P2" || true
wipefs -n "$TARGET_P1" "$TARGET_P2"
```

Use `wipefs -n` first. Do not run `wipefs -a` unless stale signatures block `mdadm --add` and a human approves.

### Phase 3: Add Target Partitions To Existing Arrays

Add the small partition to `md1` and the large partition to `md0`:

```bash
mdadm --manage /dev/md1 --add "$TARGET_P1"
mdadm --manage /dev/md0 --add "$TARGET_P2"
```

Expected immediate result:

```bash
cat /proc/mdstat
mdadm --detail /dev/md0
mdadm --detail /dev/md1
```

You should see resync/recovery in progress and two devices attached. The status may look like `[U_]` during early add, then progress toward `[UU]`.

Monitor rebuild:

```bash
watch -n 10 cat /proc/mdstat
```

Do not reboot during rebuild. Avoid heavy backup jobs while rebuild is active.

### Phase 4: Post-Rebuild Metadata Update

After `/proc/mdstat` shows both arrays as `[UU]` and no recovery in progress:

```bash
cat /proc/mdstat
mdadm --detail /dev/md0
mdadm --detail /dev/md1
```

Refresh mdadm config while preserving a backup:

```bash
cp -a /etc/mdadm/mdadm.conf /etc/mdadm/mdadm.conf.$(date +%Y%m%dT%H%M%S).bak
mdadm --detail --scan > /tmp/mdadm.scan
```

Review `/tmp/mdadm.scan`. It should contain the same array UUIDs already seen:

```text
ARRAY /dev/md/1 metadata=1.2 UUID=1e1fdea3:763de1ed:c3a77e60:b538f7c9
ARRAY /dev/md/0 metadata=1.2 UUID=46036c3b:a4d1e0fd:52ae7edb:6fbf13c3
```

If correct, replace only the `ARRAY` lines in `/etc/mdadm/mdadm.conf` with the scan output, then:

```bash
update-initramfs -u
```

This keeps initramfs able to assemble the md arrays at boot. It does not by itself make root boot from md0.

### Phase 5: fstab Review Before Any Reboot

Current `/etc/fstab` is inconsistent. Before any reboot, a human and orchestrator must choose one of these two approaches.

Option 5A: keep the current live root on `/dev/sda2` and use md0 only for `/srv/critical-backups`.

This is the conservative backup-RAID path. It requires changing `/etc/fstab` so `/` names the real root filesystem and optionally adding `/srv/critical-backups` as md0:

```text
UUID=4c773429-f3a2-4d65-b741-0ff8d9f895ab / ext4 defaults 0 1
UUID=f7c1c555-e222-42bc-880e-c1772d3a5539 /srv/critical-backups ext4 defaults,nofail 0 2
```

Do not apply this automatically without review, because the critical backup script also mounts `/dev/md0` when needed. If fstab owns the mount, the script behavior remains acceptable, but the team should agree on one mount owner.

Option 5B: migrate root to md0.

This is not a simple fstab edit. It requires Strategy B.

### Phase 6: Validate Backup Services And Frontend

Run a lightweight validation after rebuild:

```bash
findmnt -T /srv/critical-backups -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,OPTIONS
cat /proc/mdstat
```

Run one database backup outside peak hours:

```bash
cd /home/ssf/Documents/Github/database-server
DB_BACKUP_DIR=/srv/critical-backups/database-server DB_BACKUP_RETENTION_DAYS=14 ./scripts/backup-all-databases.sh
find /srv/critical-backups/database-server -maxdepth 2 -type f -name '*.gz' -exec gzip -t {} \;
```

Run or wait for the critical backup:

```bash
systemctl start alfares-critical-backup.service
systemctl --no-pager -l status alfares-critical-backup.service
```

Validate evidence:

```bash
python3 -m json.tool /home/ssf/Documents/Github/database-server/backup-evidence/latest.json
python3 -m json.tool /home/ssf/Documents/Github/shared/runtime-evidence/vault-backups/latest.json
```

Validate frontend API without printing tokens:

```bash
TOKEN=$(kubectl get secret backups-microservice-secret -n statex-apps -o jsonpath='{.data.SERVICE_TOKEN}' | base64 -d)
curl -sk -H "Authorization: Bearer $TOKEN" https://backups.alfares.cz/dashboard/summary > /tmp/backups-dashboard-summary-after-raid.json
node - <<'NODE'
const fs = require("fs");
const data = JSON.parse(fs.readFileSync("/tmp/backups-dashboard-summary-after-raid.json", "utf8"));
const db = data.external_evidence?.database_server;
const vault = data.external_evidence?.vault;
console.log(JSON.stringify({
  database_status: db?.status,
  database_backup_dir: db?.storage?.backup_dir,
  database_run_dir: db?.storage?.run_dir,
  database_artifact_count: db?.artifact_count,
  vault_status: vault?.status,
  vault_backup_dir: vault?.storage?.backup_dir,
  vault_run_dir: vault?.storage?.run_dir,
  vault_artifact_count: vault?.artifact_count,
}, null, 2));
NODE
```

Expected:

```text
database_status: success
vault_status: success
backup dirs under /srv/critical-backups
```

### Phase 7: Re-enable Any Temporarily Paused Backup Jobs

If the timer or cron was paused, restore it:

```bash
systemctl unmask --runtime alfares-critical-backup.service || true
systemctl list-timers --all --no-pager | grep alfares-critical-backup
crontab -l | grep backup-all-databases
```

## Strategy B: Separate Root/Boot RAID1 Migration Design

This section is for planning only. Do not execute it as part of Strategy A.

Objective: make the host continue booting and running if either SATA disk fails.

Why this is separate:

- current live root is `/dev/sda2`;
- current md0 is mounted at `/srv/critical-backups` and contains backup data, not the live root filesystem;
- `/dev/sdb1` is an md member, not an EFI System Partition;
- the only EFI mount currently is `/dev/sda1`;
- the UEFI boot entry points at the duplicated partition GUID `809a3f27-fe06-4050-bfb1-94a90dd7caa5`, which exists on both `sda1` and `sdb1`;
- root migration needs bootloader and initramfs work, plus proof that each disk can boot alone.

Minimum Strategy B planning requirements:

1. Create verified off-host backups of:
   - database logical dumps;
   - Vault/Kubernetes critical backup artifacts;
   - `/etc`, `/boot`, `/boot/efi`, `/var/lib/rancher/k3s`, `/opt/vault/data`;
   - `/home/ssf/Documents/Github` if not already protected elsewhere.
2. Decide the target layout:
   - root on mdraid;
   - separate ESP on both disks, not mdraid metadata 1.2;
   - optional separate mdraid array for `/srv/critical-backups`;
   - whether `/mnt/docker-data` should remain NVMe or be mirrored separately.
3. Schedule a maintenance window with console/IPMI access.
4. Boot from a rescue environment or use a staged migration that can be rolled back.
5. Build new arrays or reshape existing arrays only after a written rollback plan.
6. Copy root filesystem with `rsync -aHAXx` or equivalent from the chosen source.
7. Update `/etc/fstab`, `/etc/mdadm/mdadm.conf`, initramfs, and GRUB.
8. Install GRUB/EFI bootloader to both disks.
9. Test boot with disk A disconnected, then with disk B disconnected.

This is not currently ready to execute because these facts are missing:

- [MISSING: physical disk bay mapping for serial ZTT015X4 and ZTT015D0]
- [MISSING: whether the server supports hot-swap]
- [MISSING: desired final root/backup layout]
- [MISSING: console/IPMI access for boot recovery]
- [MISSING: off-host backup target and restore test]

## Parallel Execution Plan

### Workstream 1: Disk Identity And Hardware Mapping

- Status: ready now, read-only.
- Owner role: hardware/storage operator.
- Objective: map Linux devices to physical bays and serial numbers.
- Allowed actions: `lsblk`, `/dev/disk/by-id`, `smartctl -i` if installed, chassis labels, out-of-band controller view.
- Forbidden actions: wipe, partition, add to mdadm, unplug active `sdb`.
- Output: signed-off target disk serial and bay.
- Validation evidence: photo or console inventory plus `lsblk` serial match.

### Workstream 2: Backup RAID Repair Execution

- Status: dependency-gated by Workstream 1 and human approval.
- Owner role: root storage agent.
- Objective: add a confirmed fresh target disk to `/dev/md1` and `/dev/md0`.
- Allowed files/devices: confirmed new target disk only, `/etc/mdadm/mdadm.conf`, initramfs update.
- Forbidden files/devices: `/dev/sda`, `/dev/sdb`, `/dev/nvme0n1`, application data paths, database contents.
- Validation owner: orchestrator.
- Merge/order: execute after Workstream 1; validation after rebuild.

### Workstream 3: fstab/Boot Consistency Review

- Status: ready for planning, not execution.
- Owner role: boot/storage architect.
- Objective: resolve current mismatch between live root `/dev/sda2` and `/etc/fstab` root entry for md0.
- Allowed actions now: read-only config review and proposed patch.
- Forbidden actions now: reboot, `update-grub`, `grub-install`, root filesystem migration.
- Output: approved fstab/boot plan.
- Dependency: must be completed before any planned reboot.

### Workstream 4: Root RAID1 Migration

- Status: blocked until explicit approval and maintenance window.
- Owner role: senior storage/root migration agent.
- Objective: make host bootable from either SATA disk.
- Allowed actions: none until approved.
- Blockers: missing physical mapping, missing console access confirmation, missing target layout decision.

### Workstream 5: Application Backup Validation

- Status: ready after Workstream 2 rebuild completes.
- Owner role: application/platform validation agent.
- Objective: prove database and Vault/Kubernetes backups still run and remain visible in `backups-microservice`.
- Expected output: `/dashboard/summary` JSON with database and Vault statuses `success`.
- Merge/order: final validation after storage owner declares md arrays `[UU]`.

## Rollback And Emergency Notes

If the wrong target disk is selected but no destructive command has run:

- stop immediately;
- collect `lsblk`, `blkid`, `cat /proc/mdstat`;
- ask for human decision.

If `mdadm --add` fails:

- do not retry with another disk name;
- collect:

```bash
cat /proc/mdstat
mdadm --detail /dev/md0
mdadm --detail /dev/md1
mdadm --examine "$TARGET_P1" "$TARGET_P2"
journalctl -k -n 200 --no-pager
```

If rebuild starts but errors appear:

- do not reboot;
- do not remove the active `sdb` member;
- collect kernel logs and mdadm detail;
- consider pausing heavy services only after human approval.

If current active member `sdb` starts failing during rebuild:

- stop non-essential writes if possible;
- prioritize copying `/srv/critical-backups` to off-host storage;
- do not attempt root migration at the same time.

## Agent Prompt For Future Execution

Use this prompt for the future root-capable implementation agent only after the human has confirmed the new target disk serial:

```text
You are repairing Alfares degraded Linux mdraid backup storage. Follow /home/ssf/Documents/Github/database-server/docs/orchestrator/RAID1_RECOVERY_ORCHESTRATOR_PLAN.md exactly.

Objective: restore /dev/md0 and /dev/md1 from clean,degraded [U_] to clean [UU] by adding the human-approved fresh target disk. Do not use /dev/sda, /dev/sdb, or /dev/nvme0n1 as the target.

Current known source member:
- /dev/sdb1 -> /dev/md1 active member
- /dev/sdb2 -> /dev/md0 active member

Before destructive work:
- confirm target disk by /dev/disk/by-id and serial;
- prove no backup process is active;
- prove target has no mounted filesystems;
- capture metadata bundle under /root/raid-recovery-<timestamp>;
- ask for final approval if any current fact differs from the plan.

After adding target partitions:
- monitor /proc/mdstat until [UU];
- update /etc/mdadm/mdadm.conf ARRAY lines from mdadm --detail --scan;
- run update-initramfs -u;
- do not reboot;
- validate database and Vault evidence through backups-microservice /dashboard/summary.

Return exact commands, key outputs, residual risks, and the next required human decision.
```

## Final Decision Required Before Implementation

Choose one:

1. Repair only the backup RAID by adding a fresh new disk to current `/dev/md0` and `/dev/md1`.
2. Plan a full root/boot RAID1 migration so the server can boot and run from either SATA disk.
3. Keep current design and add off-host backup instead of trying to mirror with only the two existing SATA disks.

Do not proceed until the selected option and target disk serial are explicit.
