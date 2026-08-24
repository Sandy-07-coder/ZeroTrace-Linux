# ZeroTrace OS — Phase 3: Ephemeral Storage & Cryptographic Erasure

*Scope: Linux (Ubuntu) only. (Previously labeled Phase 2, renumbered now that the logout/switch-user GUI is Phase 2.)*

## Focus

Eliminating physical SSD wear and achieving forensic-level security through memory isolation and instant key destruction. Where Phase 1 and Phase 2 clean up *after the fact* (delete files once told to), Phase 3 changes the architecture so there's nothing recoverable to delete in the first place.

## Dynamic Encrypted Workspace Mounting

- Implement a kernel-level `tmpfs` mount to store `~/.cache` and session temp data purely within volatile RAM (`mount -t tmpfs -o size=<limit> tmpfs <mountpoint>`).
- Bind-mount or redirect the real `~/.cache` (and optionally `/tmp` for the session) onto this `tmpfs` mount at session start, so applications write to it transparently without needing to know anything changed.
- Because `tmpfs` contents live only in RAM, they're gone the instant the mount is torn down or the system loses power — no disk write ever happens for this data, which also reduces SSD wear (the point called out in the phase focus).

## In-Memory Ephemeral Key Lifecycle

- Generate a cryptographically secure random key on user login (`os.urandom(32)` for AES-256), held exclusively in the process memory of the ZeroTrace daemon — never written to disk, never logged.
- Protect that memory from being paged to swap using `mlock()` (Linux) so the key itself can't leak via the same swap-based recovery attack the project set out to prevent in Phase 1's threat model.
- Route sensitive working directories into this isolated layer: compiler build workspaces, data science cache files (e.g. Jupyter/pip caches), and browser working directories — the same categories of transient, high-value data identified in Phase 1's directory mapping.
- If encrypting the `tmpfs` contents at rest matters for your threat model (e.g. RAM could theoretically be cold-booted), layer `dm-crypt` on a loop device backed by the `tmpfs` file, keyed with the in-memory key, rather than relying on `tmpfs` alone.

## Crypto-Shredding Mechanism

- On session end (triggered by the same logout/switch-user detection built in Phase 2), the daemon:
  1. Triggers immediate zero-fill de-allocation of the in-memory key, so it's irrecoverable even via a memory dump taken moments later.
  2. Unmounts the `tmpfs` (or `dm-crypt` volume), which discards its contents entirely since they only ever existed in RAM.
- Because the data was encrypted (or existed only in volatile memory) the whole time, destroying the key or unmounting the RAM-backed store makes the data unrecoverable **without needing a multi-pass disk overwrite** — this is the core efficiency argument over Phase 1's `shred`-based approach: crypto-shredding is milliseconds, `shred` is proportional to file size and disk speed.

## Milestone Deliverable

A zero-touch storage architecture where:
- Session data (cache, temp, routed workspace directories) is isolated inside an ephemeral, RAM-backed (and optionally encrypted) mount from the moment the session starts.
- On session end, the mount is invalidated and the key destroyed within milliseconds — no user interaction and no slow disk-wipe pass required.
- The Phase 2 GUI's "Clean now" action, when this phase is active, becomes a near-instant key-destruction call instead of a file-deletion pass.

## Testing Approach

- Verify via `mount` / `findmnt` that target directories are genuinely backed by `tmpfs` (or the `dm-crypt` volume) and not silently falling back to disk.
- Confirm `mlock()` is actually preventing the key from appearing in swap: force memory pressure, then inspect swap (`swapon`, then a controlled swap dump) to confirm no key material is present.
- Timing test: measure how long crypto-shredding takes versus how long a Phase 1 `shred`-based wipe of equivalent data takes, to substantiate the "faster and equally secure" claim in your final report.
- Forensic verification: after unmount, attempt to recover any test data placed in the `tmpfs`/encrypted mount using standard file-recovery tools, and confirm nothing is retrievable.

## Relationship to Phase 1 and Phase 2

Phase 1 proved *what* needs cleaning and built the deletion/lock-handling logic. Phase 2 made cleanup interactive and tied it to real logout/switch-user events. Phase 3 makes the underlying storage itself ephemeral, so the Phase 2 dialog's "Clean now" path becomes a key-destruction call rather than a deletion pass — the visible user experience from Phase 2 doesn't need to change, only what happens underneath it when confirmed.
