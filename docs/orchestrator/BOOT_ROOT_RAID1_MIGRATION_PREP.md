# Boot/Root RAID1 Migration Preparation

Status: preparation only. No storage migration, RAID repair, bootloader update, reboot, repartitioning, filesystem wipe, or mdraid membership change is approved by this document.

Last reviewed: 2026-06-25, after fresh database backup validation.

## Intent Preservation Chain

- Vision: keep the Alfares host bootable, operational, and restorable after a SATA disk failure without losing database, Vault, Kubernetes, or application state.
- Goal Impact: choose the correct storage recovery path before touching disks, so the team does not confuse degraded backup RAID repair with a full boot/root RAID1 migration.
- System: Alfares physical host storage, Linux mdraid, UEFI/GRUB boot path, Kubernetes-backed `database-server`, root-managed critical backup service, and `backups-microservice` evidence surface.
- Feature: root/storage migration readiness review for making the host boot and run from a mirrored design.
- Task: produce a conservative preparation document after confirming fresh backup evidence, without executing destructive storage actions.
- Execution Plan: preserve current evidence, compare the two recovery strategies, list blockers, define staged migration gates, define rollback expectations, and split safe parallel workstreams.
- Coding Prompt: [MISSING: implementation prompt requires explicit human decision on final layout, target disk serial, maintenance window, console access, and rollback owner].
- Code: documentation only, `docs/orchestrator/BOOT_ROOT_RAID1_MIGRATION_PREP.md`.
- Validation: database backup run `20260625_204009` is gzip-valid and visible as `success`; Vault/Kubernetes evidence is visible as `success`; authenticated dashboard summary returned HTTP 200 with both external evidence statuses `success`; `git diff --check` must pass after this document is written.

## Fresh Backup And Evidence Baseline

Database backup was refreshed before writing this migration prep:

- Command source: `/home/ssf/Documents/Github/database-server/scripts/backup-all-databases.sh`.
- Backup target: `/srv/critical-backups/database-server`.
- Run directory: `/srv/critical-backups/database-server/20260625_204009`.
- PostgreSQL artifact: `postgres_all_20260625_204009.sql.gz`.
- Redis artifact: `redis_20260625_204009.rdb.gz`.
- Gzip validation: both `.gz` artifacts passed `gzip -t`.
- Evidence file: `/home/ssf/Documents/Github/database-server/backup-evidence/latest.json`.
- Evidence status: `success`.
- Database count: 38.
- Artifact count: 2.
- Evidence generated at: `2026-06-25T18:42:21.003537+00:00`.

Vault/Kubernetes critical evidence was validated but not freshly rerun in this session:

- Root-managed service: `alfares-critical-backup.service`.
- Latest evidence file: `/home/ssf/Documents/Github/shared/runtime-evidence/vault-backups/latest.json`.
- Latest run directory: `/srv/critical-backups/alfares-critical/20260625T170651Z`.
- Evidence status: `success`.
- Artifact count: 13.
- Evidence generated at: `2026-06-25T17:21:53.021212+00:00`.
- Fresh service start blocker: current SSH user is `ssf`; passwordless sudo is unavailable; `systemctl start --no-ask-password alfares-critical-backup.service` requires interactive authentication.

Authenticated frontend validation was completed without printing the service token:

- URL: `https://backups.alfares.cz/dashboard/summary`.
- HTTP status: 200.
- `external_evidence.database_server.status`: `success`.
- `external_evidence.database_server.storage.run_dir`: `/srv/critical-backups/database-server/20260625_204009`.
- `external_evidence.vault.status`: `success`.
- `external_evidence.vault.storage.run_dir`: `/srv/critical-backups/alfares-critical/20260625T170651Z`.

## Current Storage Facts

Read-only facts confirmed on 2026-06-25:

- `/dev/sda`, serial `ZTT015X4`, is the live boot/root disk.
- `/dev/sda1` is mounted at `/boot/efi`.
- `/dev/sda2` is mounted at `/` and also carries live bind/local-path data.
- `/dev/sdb`, serial `ZTT015D0`, is the only active mdraid source disk.
- `/dev/sdb1` is the active member for `/dev/md1`.
- `/dev/sdb2` is the active member for `/dev/md0`.
- `/dev/md0` is mounted read-write at `/srv/critical-backups`.
- `/dev/md0` and `/dev/md1` are `clean, degraded` and show `[U_]`.
- `/dev/nvme0n1p1`, serial `S7HDNJ0Y912768Y`, backs `/mnt/docker-data` and `/home/ssf/Documents/Github`.
- `/proc/cmdline` boots root by UUID `4c773429-f3a2-4d65-b741-0ff8d9f895ab`, which is `/dev/sda2`.
- `/etc/fstab` currently maps `/` to md0 UUID `f7c1c555-e222-42bc-880e-c1772d3a5539`, contradicting the live boot state.
- `/dev/sda` and `/dev/sdb` have duplicate partition GUIDs for their first and second partitions.

Do not use `/dev/sda`, `/dev/sdb`, or `/dev/nvme0n1` as a RAID repair or migration target.

## Strategy Comparison

| Topic | Degraded backup RAID repair | Full boot/root RAID1 migration |
| --- | --- | --- |
| Primary objective | Restore `/dev/md0` and `/dev/md1` from one active member to two active members. | Make the host boot and run if either SATA disk fails. |
| Current source of truth | `/dev/sdb1` and `/dev/sdb2` are the only active mdraid members. | `/dev/sda2` is the live root filesystem; `/dev/sda1` is the live EFI system partition. |
| Backup storage impact | Keeps `/srv/critical-backups` on md0 and makes backup storage mirrored again. | Requires deciding whether backups stay on a separate md array, share a root/data layout, or move off-host. |
| Boot resilience | Does not make the current root filesystem mirrored or independently bootable from both disks. | Must design ESPs, bootloader entries, initramfs/mdadm assembly, fstab, and boot tests for both disks. |
| Runtime risk | Lower if a new, confirmed, unused disk is added to the existing degraded arrays. | High; root filesystem, boot path, partition identity, and rollback all change. |
| Reboot requirement | Usually no reboot for online mdraid repair, unless hardware discovery requires it. | Requires a maintenance window and console/IPMI because bootability must be tested and recoverable. |
| Main blocker | No confirmed safe replacement/new target disk serial. | Multiple blockers: hardware mapping, console access, off-host backup, layout design, fstab mismatch, duplicate GUIDs, and current live root on `/dev/sda2`. |
| Current readiness | Dependency-gated; can proceed only after target disk confirmation and explicit approval. | Planning-only; not ready for implementation. |

## Migration Blockers

1. Physical disk bay mapping is missing.
   - Need a verified map from Linux devices and serials to physical bays.
   - Current known serials: `ZTT015X4` -> `/dev/sda`, `ZTT015D0` -> `/dev/sdb`, `S7HDNJ0Y912768Y` -> `/dev/nvme0n1`.

2. Replacement or new disk serial is not confirmed.
   - A target disk must be distinct from `/dev/sda`, `/dev/sdb`, and `/dev/nvme0n1`.
   - No target can be selected by drive letter alone.

3. Console/IPMI access is not confirmed.
   - Root migration cannot be approved without an out-of-band recovery path.
   - SSH-only access is not enough for bootloader, initramfs, or fstab failures.

4. Off-host backup and restore proof is missing.
   - Current fresh database backup and Vault/Kubernetes evidence live on `/srv/critical-backups`, which is backed by degraded md0 on `/dev/sdb2`.
   - A root migration needs a verified off-host copy and at least one restore-readiness check for critical artifacts.

5. `/etc/fstab` conflicts with the live root state.
   - Live root is `/dev/sda2` UUID `4c773429-f3a2-4d65-b741-0ff8d9f895ab`.
   - `/etc/fstab` currently declares `/` as md0 UUID `f7c1c555-e222-42bc-880e-c1772d3a5539`.
   - Any reboot before resolving this contradiction is a boot risk.

6. Duplicate GPT and PARTUUID state exists across `/dev/sda` and `/dev/sdb`.
   - Duplicate partition GUIDs can mislead boot tooling, operators, and recovery scripts.
   - The migration design must include a unique identifier plan before any disk rewrite.

7. Bootloader and EFI design is unresolved.
   - Current EFI mount is `/dev/sda1`.
   - `/dev/sdb1` is an mdraid member, not a mounted EFI system partition.
   - A full root RAID1 design must decide whether each SATA disk gets its own ESP and how boot entries are created and validated.

8. `/dev/sda2` is the live root filesystem.
   - It cannot be treated as an empty RAID member.
   - Root migration requires a staged copy/cutover or rescue-environment workflow.

9. `/dev/sdb` is the current mdraid source.
   - It is the only active member for both degraded arrays.
   - It must not be unplugged, wiped, repurposed, or used as a migration target before data is protected elsewhere.

10. Fresh root-managed Vault/Kubernetes backup rerun is blocked by sudo.
    - Existing evidence is `success`, but this session could not start the service because interactive authentication is required.
    - A human with sudo/root must run or authorize the service before a migration window.

## Safe Staged Migration Plan

This plan is intentionally command-free. It defines gates and ownership, not executable disk steps.

### Stage 0: Decision Freeze And Evidence Capture

- Confirm the selected objective: backup RAID repair only, full boot/root RAID1 migration, or off-host backup-first redesign.
- Preserve the fresh database run and current Vault/Kubernetes evidence references.
- Capture read-only storage, fstab, boot, mdraid, and by-id inventories.
- Gate: if any current disk serial, mount source, mdraid state, or backup evidence differs from this document, stop and re-review.

### Stage 1: Hardware And Access Readiness

- Map each physical SATA bay to serial number.
- Confirm whether the server supports hot-swap or needs a power-down window for disk replacement.
- Confirm console/IPMI access with a named recovery owner.
- Confirm rescue media availability and boot order recovery process.
- Gate: no root migration without console/IPMI and physical serial mapping.

### Stage 2: Off-Host Backup Readiness

- Copy fresh database backup artifacts off the degraded md0 storage.
- Copy the latest root-managed critical backup artifacts off the degraded md0 storage.
- Include `/etc`, `/boot`, `/boot/efi`, mdadm metadata, fstab, Kubernetes state, Vault state, and the Git/Docker data protection decision.
- Validate that the off-host copy can be read and that compressed artifacts pass integrity checks.
- Gate: no disk rewrite without off-host backup evidence and a named restore owner.

### Stage 3: Target Layout Design

- Decide final disk layout before implementation.
- Required decisions:
  - root on mdraid or another mirrored layout;
  - separate ESP on each SATA disk;
  - whether `/srv/critical-backups` remains a separate md array;
  - whether NVMe `/mnt/docker-data` remains single-disk or gets separate protection;
  - how duplicate GUIDs are eliminated;
  - how mount ownership is split between fstab and backup scripts.
- Gate: design must include a rollback path to the current `/dev/sda2` root until cutover is verified.

### Stage 4: Rehearsal And Rollback Plan

- Write an implementation prompt only after the layout is approved.
- Rehearse the sequence on a non-production VM or documented dry run where possible.
- Define exact stop points:
  - before first disk metadata write;
  - after target disk preparation but before root copy;
  - after root copy but before bootloader change;
  - after bootloader change but before reboot;
  - after first boot test.
- Gate: every stop point needs an operator, expected evidence, and rollback action.

### Stage 5: Maintenance Window Execution

- Freeze or pause backup jobs only as approved for the window.
- Refresh database and root-managed critical backups immediately before the maintenance window if sudo/root is available.
- Execute the approved migration prompt from console-aware root access.
- Do not combine backup RAID repair and root migration unless the final design explicitly requires it and rollback ownership is clear.
- Gate: no reboot until fstab, mdadm assembly, initramfs, bootloader entries, and console recovery are reviewed.

### Stage 6: Boot And Runtime Validation

- Confirm the host boots the intended root device.
- Confirm both SATA disk boot paths if the final objective is two-disk boot resilience.
- Confirm `/srv/critical-backups` is mounted from the intended storage device.
- Confirm `/proc/mdstat` and mdadm detail match the approved layout.
- Run database backup validation and check gzip integrity.
- Run or wait for root-managed critical backup and validate evidence.
- Validate `https://backups.alfares.cz/dashboard/summary` with database and vault statuses `success`.
- Gate: do not close the migration until boot, mount, backup, and dashboard evidence are all captured.

## Rollback Expectations

- Before disk metadata changes: abort with no storage changes and keep current boot path.
- After target preparation but before boot changes: keep the host booting from current `/dev/sda2`; do not reboot into unapproved paths.
- After root copy but before bootloader changes: discard the staged copy if validation fails; keep current root as source of truth.
- After bootloader or initramfs changes but before reboot: restore reviewed config backups if checks fail; do not reboot into uncertain config.
- After failed reboot: use console/IPMI or rescue media to boot the known-good root or restore from off-host backups.
- If `/dev/sdb` shows failure signs during any stage: stop migration, reduce non-essential writes, prioritize off-host copy of `/srv/critical-backups`, and do not attempt simultaneous root migration.

## Parallel Execution Section

### Workstream A: Hardware Mapping

- Status: ready now for a human/storage operator; not executable by SSH-only Codex.
- Owner role: hardware operator.
- Objective: map `/dev/sda`, `/dev/sdb`, and any new disk to physical bay and serial.
- Scope: chassis labels, provider panel, IPMI/controller inventory, photos, read-only Linux serial evidence.
- Allowed files/devices: none for mutation.
- Forbidden actions: unplugging active `/dev/sdb`, wiping, repartitioning, mdraid changes.
- Expected output: signed target disk serial and bay map.
- Dependencies: physical or out-of-band access.
- Blockers: [MISSING: bay mapping], [MISSING: new disk serial].
- Validation owner: storage orchestrator.
- Handoff notes: no migration prompt can be issued without this output.

### Workstream B: Off-Host Backup Readiness

- Status: dependency-gated by off-host destination decision and sudo/root for critical backup refresh.
- Owner role: backup/restore operator.
- Objective: prove database and critical backup artifacts exist outside the degraded md0 storage.
- Scope: fresh DB run, Vault/Kubernetes critical run, host config backup, artifact integrity checks, restore-readiness notes.
- Allowed files/devices: backup artifacts and off-host destination only.
- Forbidden actions: production restore, live DB mutation, destructive disk work.
- Expected output: off-host path, copy timestamps, integrity result, restore owner.
- Dependencies: [MISSING: off-host target], sudo/root for fresh critical backup rerun.
- Blockers: `alfares-critical-backup.service` requires interactive auth in this session.
- Validation owner: platform validation agent.
- Handoff notes: existing Vault evidence is success but not freshly rerun by this session.

### Workstream C: Boot Layout Architecture

- Status: ready for planning, not execution.
- Owner role: senior boot/storage architect.
- Objective: choose final root, ESP, mdraid, fstab, and bootloader layout.
- Scope: design document only.
- Allowed files: docs under `docs/orchestrator/`.
- Forbidden files/actions: `/etc/fstab`, `/etc/mdadm/*`, bootloader files, initramfs, reboot.
- Expected output: approved layout and rollback design.
- Dependencies: hardware map and off-host backup strategy.
- Blockers: unresolved fstab contradiction and duplicate GUID policy.
- Validation owner: root/storage orchestrator.
- Merge order: after Workstream A, before any implementation prompt.

### Workstream D: Backup RAID Repair

- Status: dependency-gated and separate from root migration.
- Owner role: root storage agent.
- Objective: restore existing `/dev/md0` and `/dev/md1` to two-member health if the selected objective is only backup RAID repair.
- Scope: confirmed new target disk only, mdraid metadata, backup validation.
- Allowed files/devices: only a human-approved target disk and necessary mdadm metadata after approval.
- Forbidden devices: `/dev/sda`, `/dev/sdb`, `/dev/nvme0n1`.
- Expected output: mdraid health evidence and backup/dashboard evidence.
- Dependencies: target serial, maintenance/IO window, explicit human approval.
- Blockers: [MISSING: target disk serial].
- Validation owner: application/platform validation agent.
- Merge order: can precede full root migration only if the team chooses backup RAID repair as an interim step.

### Workstream E: Full Root Migration Implementation

- Status: blocked.
- Owner role: senior root migration agent with console-aware operator.
- Objective: migrate to a design that boots and runs from mirrored SATA storage.
- Scope: only the future approved implementation prompt.
- Allowed files/devices: none until explicit approval.
- Forbidden actions now: storage writes, bootloader changes, initramfs changes, fstab changes, reboot.
- Expected output: [MISSING: implementation prompt], [MISSING: validation package].
- Dependencies: Workstreams A, B, and C; maintenance window; console/IPMI.
- Blockers: physical mapping, target serial, off-host backups, boot layout approval, rollback owner.
- Validation owner: independent platform validation agent.
- Merge order: final integration only after all previous workstreams are complete.

## Next Human Decision

Choose one objective before any implementation prompt is written:

1. Repair only the degraded backup RAID with a confirmed fresh target disk.
2. Prepare a full boot/root RAID1 migration with off-host backups, console/IPMI, and a maintenance window.
3. Keep current root layout and prioritize off-host backups instead of changing boot storage now.

Current recommendation: do not start full boot/root migration until hardware bay mapping, replacement disk serial, console/IPMI, off-host backup target, and boot layout are all confirmed.
