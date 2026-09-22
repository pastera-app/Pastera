# Verification

## Default Automated Check

Run from the repository root:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  clean test
```

Expected result: `** TEST SUCCEEDED **`.

## OneDrive Focused Automated Checks

Run focused sync checks while iterating on OneDrive behavior:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:pasteraTests/SyncCoordinatorTests \
  -only-testing:pasteraTests/PreferencePaneAlignmentTests \
  -only-testing:pasteraTests/SyncPreferenceOneDriveLocationTests \
  -only-testing:pasteraTests/PasteboardContentTests \
  test
```

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:pasteraTests/PasteboardHistoryRepositoryTests \
  -only-testing:pasteraTests/SnippetRepositorySyncTests \
  test
```

Expected result: both commands end with `** TEST SUCCEEDED **`. With Swift
Testing, verify the console lists the intended suite names; a build-only pass is
not enough.

## Password Vault Focused Automated Check

Run the complete local-first password-vault and shared UI boundary set:

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  test \
  -only-testing:pasteraTests/PasswordVaultLocalStorageTests \
  -only-testing:pasteraTests/PasswordVaultMigrationTests \
  -only-testing:pasteraTests/PasswordVaultCloudReplicaTests \
  -only-testing:pasteraTests/PasswordVaultSyncMetadataTests \
  -only-testing:pasteraTests/PasswordVaultSyncServiceTests \
  -only-testing:pasteraTests/PasswordVaultStoreTests \
  -only-testing:pasteraTests/PasswordVaultMasterPasswordTests \
  -only-testing:pasteraTests/PasswordVaultMenuTests \
  -only-testing:pasteraTests/PasswordVaultSecuritySettingsTests \
  -only-testing:pasteraTests/VaultAutomationUnlockKeyStoreTests \
  -only-testing:pasteraTests/SyncCoordinatorTests \
  -only-testing:pasteraTests/SyncPreferenceTopSectionTests \
  -only-testing:pasteraTests/PreferencePaneAlignmentTests \
  -only-testing:pasteraTests/MainMenuEmbeddedContentTests \
  -only-testing:pasteraTests/MainMenuVisualPolishTests \
  -only-testing:pasteraTests/MainMenuVaultSyncFooterTests \
  -only-testing:pasteraTests/MainMenuOneDriveFooterTests \
  -only-testing:pasteraTests/MainMenuOneDriveInstallationFooterTests \
  -only-testing:pasteraTests/MainMenuOneDriveStatusAssetTests \
  -only-testing:pasteraTests/MainMenuFooterButtonActionTests \
  -only-testing:pasteraTests/OneDriveProcessStatusServiceTests
```

Expected result: `** TEST SUCCEEDED **`, with all 21 named Swift Testing suites
listed in the console.

## Password Vault Manual Lifecycle Matrix

Use a temporary Application Support directory or a test build with an isolated
bundle identifier, plus a dedicated OneDrive test subdirectory. Never point a
destructive test at the user's existing `PasteraVault.kdbx`.

| Scenario | Exercise | Required result |
| --- | --- | --- |
| No OneDrive | Create a local-only vault, lock, restart, unlock, and perform folder and entry CRUD without a OneDrive account or process. | No OneDrive prompt blocks the vault; mode remains local-only; nothing is created in OneDrive. |
| Settings separation | Toggle history/snippet upload and import switches, then inspect the password-vault summary. | The password-vault mode does not change. A local-only vault shows one **Enable OneDrive Sync** action when the selected root is valid; an enabled vault shows no disable or delete action. |
| Main OneDrive icon | Click the footer icon with OneDrive running, stopped, and missing while different Pastera pages are open. | Running activates OneDrive, stopped launches it, and missing only reports status. Pastera stays on the current page in every case. |
| Sudden disconnect | Enable password-vault sync, stop OneDrive, then add, edit, move, and delete entries. | Local operations succeed; the footer shows a red disconnected shape and accessible text; pending count increases; the remote KDBX is unchanged. |
| Reconnect | Start OneDrive after queued local changes and retry sync. | Only the local delta is uploaded; read-back digest verification clears pending and advances local/remote baselines. |
| Missing local copy recovery | Start from a compatible remote KDBX with no prepared local copy, first with OneDrive stopped and then running. | No local password error field appears. Inline **Start OneDrive** and **Try Again** recover the local copy; choosing a new local vault first shows the separate-branch warning and does not overwrite remote. |
| One-sided and concurrent changes | Change only local, only remote, then both sides using independent test copies. | The service selects upload, apply-remote, or entry-level merge; unrelated entries converge; pending clears only after verified remote read-back. |
| Entry conflict | Change the same entry on both sides with equal modification timestamps. | A `(Conflict)` copy is retained, the conflict count and yellow semantic badge are visible, and the vault stays unlocked for later review. |
| Locked merge | Lock the local vault, change both sides, and synchronize. | Phase becomes waiting-for-unlock; neither digest baseline advances and no side is overwritten; unlock resumes merge. |
| Legacy migration | Place a valid compatible remote KDBX at `PasteraSync/vault/PasteraVault.kdbx` with no local file, then restart and interrupt/restart once during migration. | A byte-verified local copy is created, the migration journal resumes safely, and migration version/baselines update only after local read-back succeeds. |
| Local corruption | Corrupt only the isolated local KDBX while retaining its backup and remote test replica. | Pastera reports a local recovery state rather than a cloud-password error; it does not overwrite the remote replica. |
| Remote corruption or partial download | Replace the isolated remote KDBX with invalid bytes or simulate a placeholder/short read. | Sync reports remote corruption/unavailability, preserves the usable local vault and all baselines, and does not upload over the suspect remote file. |
| Different remote master password | Encrypt the remote test copy with a different master password and merge once. | Only the inline remote-credentials page has a secure field; the value is one-shot memory state, clears on submit/leave, and a wrong value does not change local data or baselines. |
| Accessibility | With VoiceOver or Accessibility Inspector, traverse footer badge, settings summary, contextual recovery actions, conflict count, and remote secure field. Enable Reduce Motion and repeat syncing. | Every state has a shape plus descriptive label, keyboard order is logical, secrets never appear in labels, and reduced motion uses a static progress symbol and text. |

## Feature Checks

- History retention: create more histories than the menu display limit and
  confirm search still finds older stored items.
- Plain search: verify case-sensitive and case-insensitive text matching.
- Regex search: verify valid patterns match and invalid patterns return a
  typed error without blocking the UI.
- Pagination: verify limit/offset does not duplicate or skip sorted results.
- Image pasteboard: copy an image from Preview or a screenshot, select it from
  Pastera, and paste it into Notes and Preview.
- File pasteboard: copy one or more files in Finder, select the history item,
  and paste into Finder or a text target that accepts file URLs.
- Screen Sharing paste: enable Pastera automatic paste and its Accessibility
  permission. For local Pastera pasting into a remote Mac, enable Screen
  Sharing's Edit > Use Shared Clipboard. Focus a disposable remote text field,
  select a plain-text history item, and confirm the complete text is pasted
  without a stray `v` or a Chinese input method's `v` composition. Type another
  ordinary character afterward to confirm Command was released. Repeat with
  Pastera running on the remote Mac, and with a local text editor as the target.
- OneDrive sync simulation: use two local Pastera profiles or two macOS user
  accounts that point at the same OneDrive-backed root containing
  `manifest.json`, `histories/`, and `snippets/` directly under the selected
  `Pastera/sync` folder. No sync passphrase is required.
- OneDrive default location: with one macOS OneDrive account signed in, open the
  Sync pane and confirm Pastera selects `OneDrive > Pastera > sync` while Finder
  reveals the actual folder under
  `~/Library/CloudStorage/<OneDrive>/Pastera/sync`.
- OneDrive multiple accounts: when both personal and work OneDrive folders are
  present, open the Sync pane and confirm Pastera automatically uses the
  personal `OneDrive` root when present. With only one or several `OneDrive-*`
  work roots, confirm Pastera requires explicit folder selection and does not
  create `Pastera/sync` under the first name. Confirm English and Chinese shared
  library roots never appear as candidates.
- OneDrive missing install/login: temporarily make
  `~/Library/CloudStorage/OneDrive*` unavailable, open the Sync pane, and click
  `自动同步`, `立即同步`, and each detailed scope switch. Each sync entry point
  should report that OneDrive must be installed and logged in, and no sync
  directory should be created under `Documents`.
- OneDrive Finder reveal: with a valid default sync root, click `显示` and
  confirm Finder opens the default `Pastera/sync` folder. Move or delete the
  folder and confirm `显示` reports that the selected sync folder is
  unavailable.
- OneDrive automatic switch: confirm `自动同步` is off by default. Turn it on
  when all four detailed switches are off and confirm Pastera enables history
  upload/import and snippet upload/import automatically.
- OneDrive plaintext protocol: trigger an upload and inspect a generated record.
  Confirm the JSON has a direct `payload` object and does not contain `crypto`,
  `nonce`, `ciphertext`, or `tag`.
- OneDrive legacy encrypted records: place an old encrypted beta record with
  `nonce`, `ciphertext`, and `tag` in the sync folder, trigger import, and
  confirm it is skipped without requiring a key or passphrase.
- OneDrive first-enable behavior: create old history and snippet data before
  enabling upload, then enable history upload and snippet upload. Confirm only
  new local changes created after enabling upload produce cloud records.
- OneDrive convergence: with history import/export and snippet import/export
  enabled on both profiles, create new history and snippets on profile A,
  trigger Sync Now, then trigger Sync Now on profile B and confirm records
  appear without changing their source device identity. Repeat from B to A.
- OneDrive LWW import: create or inject an older same-ID history/snippet record
  in the selected sync folder, sync the other profile, and confirm it does not
  overwrite newer local data or increment the imported count. Then inject a
  newer same-ID record and confirm it overwrites and increments the imported
  count.
- OneDrive snippet parent context: after enabling snippet upload, change only a
  snippet inside an older folder, trigger Sync Now, and confirm the exported
  `snippets/folders/<folder-id>.json` accompanies the changed snippet without
  bumping the folder payload `updatedAt`.
- OneDrive manual status: after Sync Now, confirm status distinguishes local
  writes to the local sync folder, actual imports, no new data, and waiting for
  the OneDrive desktop client. Pastera must not claim the cloud upload itself
  has completed.
- OneDrive non-destructive import: delete an imported history item and an
  imported snippet on profile A, sync both profiles, and confirm profile B keeps
  its local data. Re-sync profile A and confirm the deleted items are not
  re-imported there.
- OneDrive conflict copies: if OneDrive creates conflict-copy JSON files, record
  them as a v1 known limitation. Pastera does not auto-merge conflict copies;
  inspect or resolve them manually before considering the shared folder
  converged.
- OneDrive missing folder: point sync at a folder that is later moved or
  unavailable, trigger Sync Now, and confirm the status reports the problem
  while local data remains unchanged.
- OneDrive file asset sync: choose at least one `文件类型`, enable the matching
  history direction (`上传历史`/`同步历史`), copy supported non-text assets
  (image, PDF, RTF/RTFD), sync two local profiles, and confirm the remote
  profile imports usable history entries.
- OneDrive file limits: copy more than 10 file assets or one file asset larger
  than 25 MiB, trigger upload, and confirm Pastera reports a file skip warning
  while smaller text history records still sync.
- OneDrive Finder file exclusion: copy a Finder file or folder, trigger upload,
  and confirm it stays out of file sync without failing text history or snippet
  sync.

## Release DMG Checks

For GitHub Release manual downloads, publish the signed and notarized PKG as
the recommended installer. Keep the DMG available as a fallback and as the
Sparkle update artifact.

Before publishing a public PKG release, build and upload the signed and
notarized installer with:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)" \
DEVELOPER_ID_INSTALLER="Developer ID Installer: Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
NOTARY_KEYCHAIN_PROFILE="PasteraNotary" \
script/package_release_pkg.sh \
  --version "2.0.1-beta"
```

For a local PKG dry run without Apple notarization credentials or Developer ID
certificates, use:

```bash
script/package_release_pkg.sh --version "2.0.1-beta" --skip-notarization
```

This dry run ad-hoc signs the app locally and creates a PKG, but the output is
not suitable for public distribution.

The PKG installs `Pastera.app` into `/Applications`, shows Chinese-first
Installer pages, and runs a postinstall script that opens Pastera with
`--pastera-open-setup-guide` when a foreground user session exists. CLI, MDM, or
no-GUI installs skip the auto-open step.

Validate a public PKG with:

```bash
pkgutil --check-signature Pastera.pkg
spctl -a -vv -t install Pastera.pkg
xcrun stapler validate Pastera.pkg
```

Before publishing a public release, build the signed and notarized DMG and
update Sparkle appcast with:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
NOTARY_KEYCHAIN_PROFILE="PasteraNotary" \
SPARKLE_PRIVATE_KEY="<private key from secrets>" \
script/package_release.sh \
  --version "2.0.1-beta" \
  --tag "v2.0.1-beta" \
  --update-appcast
```

For a local packaging dry run without Apple notarization credentials or a
Developer ID certificate, use:

```bash
script/package_release.sh --version "2.0.1-beta" --skip-notarization
```

This dry run ad-hoc signs the app locally and creates a DMG, but the output is
not suitable for public distribution.

Every DMG opens to a Finder install guide with a generated
`.background/pastera-dmg-guide.png` background, fixed icon positions, and the
fallback files `Pastera 安装说明.txt` and `Open Privacy & Security.webloc`. For
ad-hoc dry runs, confirm the guide explains the Gatekeeper "Apple cannot verify"
path through System Settings > Privacy & Security > Open Anyway or Control-click
> Open, and that the webloc opens the Privacy & Security pane. This guide is
only a user-facing fallback; Developer ID signing and notarization are still
required to avoid the Gatekeeper warning on a clean Mac.

The packaging script validates the app and DMG with:

```bash
codesign --verify --deep --strict --verbose=4 Pastera.app
spctl -a -vv Pastera.app
xcrun stapler validate Pastera.app
spctl -a -vv Pastera.dmg
xcrun stapler validate Pastera.dmg
```

If the appcast must be updated separately after the DMG is created, use:

```bash
SPARKLE_PRIVATE_KEY="<private key from secrets>" \
script/update_appcast_for_dmg.sh \
  --version "2.0.1-beta" \
  --tag "v2.0.1-beta" \
  --dmg ".build/release-artifacts/Pastera-2.0.1-beta-macOS.dmg"
```

Do not write certificate passwords, notary credentials, or Sparkle private keys
into the repository or release notes.

## DMG Accessibility Checks

- Clean install: download the DMG on a macOS 13+ machine, mount it, drag
  `Pastera.app` to `/Applications`, launch it from `/Applications`, trigger a
  snippet hotkey, grant Accessibility when prompted, restart Pastera, and
  confirm the hotkey no longer repeats the Accessibility alert. If testing an
  ad-hoc DMG, first confirm Finder opens to the visual install guide, the
  `Pastera.app`, `Applications`, and `Open Privacy & Security.webloc` icons are
  positioned without covering text, `.background/pastera-dmg-guide.png` exists,
  `.DS_Store` exists, and `Pastera 安装说明.txt` fallback steps match the current
  macOS UI.
- Direct-from-DMG guard: launch `Pastera.app` from the mounted DMG and confirm
  Pastera prompts the user to move the app to Applications before enabling
  Accessibility.
- Downloads guard: copy `Pastera.app` to `~/Downloads`, launch it, and confirm
  the same move-to-Applications prompt appears.
- Upgrade path: if an older zip/ad-hoc build was previously authorized, remove
  the old Accessibility entry or run
  `tccutil reset Accessibility com.pastera-app.Pastera`, then authorize the
  signed `/Applications/Pastera.app` once and verify subsequent signed updates
  keep the permission stable.

## Performance Checks

- Seed 1000 and 5000 text histories, then confirm menu creation only fetches
  the configured display limit.
- Search must run off the main thread or through a cancellable debounced path
  before wiring into UI.
- Large image assets should be skipped or bounded by `maxSyncedAssetBytes`
  during sync export.

## Manual Evidence

Record manual checks in task summaries, not in `AGENTS.md`. Include app/source,
target app, data type, expected result, and observed result.
