# Folder Sync

## V4 Snapshot Model

Pastera sync uses ordinary files in a folder-sync provider. On macOS today that
folder is a local OneDrive directory; the OneDrive desktop client handles cloud
transport. Pastera does not call Microsoft Graph, CloudKit, or a hosted Pastera
service. A future Windows client can write the same `Pastera/sync` structure
under its own OneDrive/AppData-backed path.

The default macOS location is:

```text
~/Library/CloudStorage/<OneDrive>/Pastera/sync
```

The settings UI shows a friendly path such as `OneDrive > Pastera > sync`
instead of exposing the hidden `Library` path. Pastera detects usable
`~/Library/CloudStorage/OneDrive*` folders, filters shared-library/temp
locations, and creates `<OneDrive>/Pastera/sync` only for the selected default
candidate. Only the exact personal root named `OneDrive` is selected
automatically. Every `OneDrive-*` work/account root requires an explicit
selection even when it is the only candidate. English and localized shared
libraries, including `Shared Libraries`, `共享的库`, and `共享库`, are
never candidates.

The settings UI allows the user to choose a sync location. On macOS the chosen
location must be inside a usable OneDrive folder and pass a write, read-back,
and cleanup probe; otherwise Pastera does not save it. A previously saved root
that is missing or points into a shared library is treated as unavailable before
new cloud writes begin. If no usable OneDrive folder is detected, sync controls
report that the user must install and log in to OneDrive. Pastera does not fall
back to `~/Documents`.

Sync is intentionally non-destructive:

- Cloud imports may create or update local history records.
- Cloud history imports do not delete local history.
- Cloud snippet imports may apply explicit folder/snippet deletion tombstones
  when the tombstone is newer than the matching local row.
- Remote absence never deletes local history or snippets.
- When a user deletes a synced local history item, Pastera records a local
  suppression entry so the same cloud item is not imported back onto that device
  later.
- When a user deletes a synced local snippet folder or item, Pastera exports a
  deletion tombstone so other devices can apply the newer snippet deletion.

## Password Vault Local-First Replica

Password vault storage has its own lifecycle and is independent from history,
snippet, and file-asset sync. Creating a password vault defaults to
`localOnly`; the OneDrive root and the four history/snippet switches do not
enable password-vault sync. The Sync settings pane only shows a password-vault
summary plus a one-way **Enable OneDrive Sync** action while the vault is still
local-only. After enabling, Settings retains the account/root, status summary,
and manual sync controls; the product UI does not offer stopping password-vault
sync or deleting its OneDrive copy. Context-specific local-copy recovery,
remote credentials, and conflict review remain in the password-vault window.

The production local working copy is stored outside OneDrive:

```text
~/Library/Application Support/com.pastera-app.Pastera/PasswordVault/
  PasteraVault.kdbx
  PasteraVault.kdbx.bak
  PasswordVaultSyncMetadata.json
```

Debug builds use their own bundle-identifier directory. The local KDBX is the
working source for every create, update, move, delete, lock, unlock, and quick
unlock operation. OneDrive availability never gates these operations after the
local copy has been prepared.

When the user explicitly enables OneDrive, the encrypted replica remains at
the compatible path used by earlier password-vault builds:

```text
<selected-OneDrive-sync-root>/PasteraSync/vault/PasteraVault.kdbx
```

`PasswordVaultSyncMetadata.json` contains only lifecycle state and digests:
mode, local and last-synced revisions, local and observed-remote SHA-256
digests, pending-merge digest, last-sync time, pending/conflict counts, failure,
and migration version. It never stores entry titles, usernames, passwords,
notes, websites, master passwords, or quick-unlock keys.

The summary baselines are updated only after the corresponding file operation
has been verified:

- `lastSyncedLocalRevision` and `lastSyncedLocalDigest` identify the verified
  local baseline.
- `lastObservedRemoteDigest` identifies the verified OneDrive baseline.
- `pendingChangeCount` remains non-zero until the encrypted remote write is
  read back and its digest matches.
- `pendingMergedRemoteDigest` prevents the same already-merged remote version
  from being merged again when a later upload retry is required.
- `lastSyncAt` records a verified password-vault synchronization, not a claim
  that Microsoft's service has finished cloud transport.

If OneDrive is not installed, stops running, or its folder becomes unavailable,
the mode remains `oneDrive`, the footer and settings summary show a disconnected
state, and local commits continue increasing the pending count. Pastera does
not read or write the remote path while the OneDrive process is unavailable.
After reconnection, it compares both digest baselines and performs one of four
decisions: no change, upload local, apply remote, or merge both.

Concurrent password-vault changes are merged at KDBX group and entry level.
Independent entries are combined; newer versions win while the older value is
retained in KDBX history (up to ten versions); equal-timestamp divergent values
produce a new entry titled with `(Conflict)`. Newer KDBX deletion tombstones
remove older matching entries or groups. A different remote master password is
accepted only as a one-shot in-memory merge credential and is cleared when the
page is submitted or left.

Once password-vault sync is enabled, the mode remains `oneDrive`. The main
OneDrive footer icon reports the desktop client's process state together with
the vault-sync badge; clicking it launches or activates OneDrive without
navigating away from the current Pastera content. If OneDrive is missing, the
icon reports that state without opening a download page.

## Directory Layout

`sync` is the protocol root. History and snippets are stored separately, and
each device writes one SQLite snapshot per kind. File assets are a separate
directory domain: metadata lives in a JSON manifest, while payloads remain as
ordinary files under the device's `assets` directory.

```text
<OneDrive>/Pastera/sync/
  history/
    protocol.json
    devices/
      <device-id>.sqlite
  snippets/
    devices/
      <device-id>.sqlite
  files/
    devices/
      <device-id>/
        manifest.json
        assets/
          <history-id>/
            <asset-index>-<byte-count>-<version>-<filename>
```

The old development protocol is not read. Pastera no longer reads
the root-level `manifest.json`, `histories/*.json`, or
`snippets/items|folders/*.json`. Each history SQLite snapshot is validated against
`schemaVersion=4`; older snapshots are skipped and preserved. Reading history
does not initialize or rewrite the shared directory or `history/protocol.json`.
This lets snapshots arrive before the protocol marker without losing data.
Writing initializes or upgrades the marker without deleting other devices'
snapshots, including when the marker is missing or incomplete. An unreadable
marker or a recognized future protocol version prevents the write and preserves
the shared files for retry or a newer app version.

Each app installation uses a persistent app-level device UUID. macOS seeds that
value from the machine UUID on first use when available, then stores it in
preferences; Windows should store an equivalent UUID under the user's app data
directory. Device snapshot file names only use cross-platform-safe characters.

Snapshots are written by generating a temporary SQLite file in the target
directory, closing the SQLite connection, then atomically replacing the target
device snapshot. WAL is disabled so OneDrive does not need to sync `-wal` or
`-shm` sidecar files.

Corrupt SQLite snapshots are skipped during import. Sync success status
reflects local file work only; Pastera does not know whether the OneDrive
desktop client has uploaded the local snapshot to the cloud.

## SQLite Schemas

History snapshot:

```sql
metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)
histories(
  id TEXT PRIMARY KEY NOT NULL,
  updatedAt INTEGER NOT NULL,
  sourceKind TEXT NOT NULL,
  text TEXT NOT NULL
)
CREATE INDEX histories_updatedAt_index ON histories(updatedAt DESC);
```

History metadata includes `schemaVersion=4`, `deviceID`, `platform`,
`generatedAt`, `historyLimit`, `maxTextBytes`, `snapshotTextBudgetBytes`, and
`windowSignature`.

History sync is text-only. `sourceKind` is one of:

- `plainText`: UTF-8 text copied as plain text.
- `url`: a non-`file://` URL serialized as its absolute string.

Images, files, PDFs, RTF, HTML, thumbnails, and raw pasteboard assets are not
stored in history sync snapshots. The history protocol does not expose macOS
`NSPasteboard` type names.

File asset snapshot:

```json
{
  "manifestVersion": 1,
  "schemaVersion": 1,
  "deviceID": "<device-id>",
  "generatedAt": 1781970000,
  "assetCount": 2,
  "histories": [
    {
      "historyID": "<history-id>",
      "updatedAt": 1781970000,
      "assets": [
        {
          "assetIndex": 0,
          "pasteboardType": "com.adobe.pdf",
          "byteCount": 1234,
          "modifiedAtNanoseconds": 1781970000000000000,
          "relativePath": "assets/<history-id>/000-1234-1781970000000000000-document.pdf",
          "originalFilename": "document.pdf"
        }
      ]
    }
  ]
}
```

The file manifest stores only metadata and relative file paths. Binary payloads
are written directly as normal files under
`files/devices/<device-id>/assets/<history-id>/`. File assets are versioned by
asset index, byte count, source modification time when available, and the
original filename. Pastera does not keep a separate local file index or hash file
contents during file sync.

Snippet snapshot:

```sql
metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)
folders(id TEXT PRIMARY KEY, title TEXT NOT NULL, displayIndex INTEGER NOT NULL,
        isEnabled INTEGER NOT NULL, updatedAt INTEGER NOT NULL,
        lastModifiedDeviceID TEXT)
snippets(id TEXT PRIMARY KEY, folderID TEXT NOT NULL, title TEXT NOT NULL,
         content TEXT NOT NULL, displayIndex INTEGER NOT NULL,
         isEnabled INTEGER NOT NULL, updatedAt INTEGER NOT NULL,
         lastModifiedDeviceID TEXT)
deletedFolders(id TEXT PRIMARY KEY, title TEXT NOT NULL, deletedAt INTEGER NOT NULL,
               deviceID TEXT)
deletedSnippets(id TEXT PRIMARY KEY, folderID TEXT NOT NULL, folderTitle TEXT NOT NULL,
                content TEXT NOT NULL, deletedAt INTEGER NOT NULL,
                deviceID TEXT)
```

Snippet metadata includes `schemaVersion=3`, `deviceID`, and `generatedAt`.
Pastera still reads `schemaVersion=2` snippet snapshots for development
compatibility, but current writes use `schemaVersion=3` so explicit deletion
tombstones can travel between devices.

Snippet snapshots remain full snapshots and may keep all snippet text. They are
independent from the text-only history protocol.

## Upload And Import

History upload writes only records whose `deviceID` matches the current device.
The exported history snapshot is ordered by `updatedAt DESC`, capped at 2000
rows, skips single text values larger than 256 KiB, and stops when the snapshot
reaches the 8 MiB text budget. The effective count is also limited by the local
stored-history retention setting. New installs default that local retention to
2000; explicit existing user settings are not force-reset.

Pastera computes a lightweight window signature from exported row IDs,
timestamps, source kinds, text byte counts, and sync limits. If the signature is
unchanged and the current device snapshot still exists, Pastera skips rewriting
the SQLite file so OneDrive has nothing new to upload.

Snippet upload writes the current complete snippet library. Folder and snippet
rows keep their `lastModifiedDeviceID`, so imported remote snippets do not
become current-device changes.

File upload writes this device's newest supported non-text clipboard assets.
The file domain is independent from text history sync and snippet sync:

- Supported file assets are images, PDF, and RTF/RTFD.
- Plain text and non-file URL history stay in the text-only history protocol.
- Finder file URL history is not part of OneDrive file sync.
- Each device exports at most 10 file assets.
- A single file asset larger than 25 MiB is skipped.
- A multi-asset history is kept whole; if it would exceed the 10-asset budget
  or contains a skipped asset, the whole history is skipped for file sync.

Import reads SQLite snapshots from other devices only. Same-ID conflicts use
last-write-wins by business timestamp:

- Remote history uses `histories.updatedAt`.
- Remote snippet folders and snippets use their `updatedAt`.
- Remote snippet deletions use `deletedAt`.
- A remote row is imported only when the local row does not exist, or the
  remote timestamp is strictly greater than the local timestamp.
- A remote snippet deletion is applied only when its `deletedAt` is greater than
  or equal to the matched local snippet or folder `updatedAt`.
- Equal or older remote rows are skipped.

Imported history rows are written locally as plain text clipboard history. URL
history also imports as plain text so it works the same across macOS and future
Windows clients.

Remote absence never deletes local data. Import counts report actual local
writes; corrupt snapshots, locally suppressed IDs, older/equal records, and
older snippet tombstones are not counted as imported.

Before opening a remote history SQLite file, Pastera compares its file size and
modification time against the last successfully processed state for that app
run. Unchanged remote snapshots are skipped without opening SQLite or running
row-level import checks.
Only snapshots whose rows were successfully processed enter that cache. A local
database write failure is reported as a failure and leaves the snapshot eligible
for retry. Unreadable snapshots remain
eligible for the next sync even when their size and modification time stay the
same; an import pass reports a warning for snapshots it cannot read. A successful
automatic import pass clears an earlier failure or warning even if it imports
no new rows.

While an import scope is enabled, Pastera watches the sync folder for remote
history/snippet snapshots and file manifests/assets. Events are coalesced for
about half a second before an import pass; the default 300-second timer remains
a fallback. This removes the polling delay after OneDrive delivers a file, but
does not control OneDrive's cloud transfer time. File assets arriving after their
manifest trigger another import attempt. The watcher ignores this device's own
files and hidden temporary files, and stops when sync is stopped or reconfigured.
An event-triggered pass imports enabled scopes without directly exporting data
or triggering password vault synchronization.

When the existing overwrite-duplicate-history preference is enabled, history
lists group plain text and RTF/HTML variants only when their complete plain text
bytes match. Grouping happens after filters and before pagination, with the most
recent matching record representing the group. Original records and formats
remain stored. Explicitly deleting a displayed group removes its matching
members and suppresses each ID locally so sync cannot immediately restore them.
Images, files, and multi-item text payloads retain their separate paste behavior.

## Sync Switches

The Sync pane separates automatic work into two main switches:

- `自动上传`: startup, timer, and local-change passes may write this device's
  history/snippet snapshots to OneDrive.
- `自动同步`: startup, timer, and remote file-change passes may import snapshots
  written by other devices.

Four detailed scope switches control text history and snippets:

- `上传历史`
- `同步历史`
- `上传片段`
- `同步片段`

When `自动上传` is turned on and both upload scopes are off, Pastera enables
history and snippet upload so the switch has meaningful work. When
`自动同步` is turned on and both import scopes are off, Pastera enables history
and snippet import.

File assets are controlled by compact icon checkboxes in the `文件类型` row of
the OneDrive account section. The default is no selected file type; choosing
image, PDF, or RTF/RTFD enables the separate `files` sync domain for the matching
history direction. This keeps text history snapshots small and fast while still
allowing selected binary assets to upload through the independent manifest/file
path.

Manual `立即同步` bypasses the two automatic main switches, but still respects
the four text/snippet scope switches and the selected file types.

## Limits

History snapshots are capped at 2000 rows per device. A single history text
value larger than 256 KiB is skipped rather than truncated. Each device snapshot
also has an 8 MiB cumulative text budget. Items skipped by these sync limits
remain in the local clipboard history when local retention allows them.

File snapshots are capped at 10 file assets per device. A single file asset
larger than 25 MiB is skipped. File skips and validation failures do not fail
text history or snippet sync; Pastera reports them as sync warnings.
