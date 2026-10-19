import AppKit
import Foundation
import LocalAuthentication
import PasteraAgentProtocol

// Agent access and observer ownership remain beside the UI facade they secure.
// swiftlint:disable file_length

protocol PasswordVaultAuthorizing {
    func authorize(reason: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void)
}

final class SystemPasswordVaultAuthorizer: PasswordVaultAuthorizing {
    func authorize(reason: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(.failure(.authenticationFailed))
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else if (error as? LAError)?.code == .userCancel || (error as? LAError)?.code == .appCancel {
                    completion(.failure(.userCancelled))
                } else {
                    completion(.failure(.authenticationFailed))
                }
            }
        }
    }
}

protocol PasswordVaultAgentAccess: AnyObject {
    var agentVaultReady: Bool { get }

    func ensureReadyForAgent(completion: @escaping (Result<Void, PasswordVaultError>) -> Void)
    func agentMetadata(
        completion: @escaping (Result<([PasswordVaultFolder], [PasswordVaultEntry]), PasswordVaultError>) -> Void
    )
    func agentPaste(
        entryID: UUID,
        field: VaultAgentSecretField,
        target: PasteTargetContext,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    )
    func agentCopy(
        entryID: UUID,
        field: VaultAgentSecretField,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    )
    func agentSecret(
        entryID: UUID,
        field: VaultAgentSecretField,
        completion: @escaping (Result<Data, PasswordVaultError>) -> Void
    )
    func disableAutomationUnlockForAgent() throws
}

// swiftlint:disable:next type_body_length
final class PasswordVaultUIController: PasswordVaultAgentAccess {
    private let store: PasswordVaultStore
    private let syncController: PasswordVaultSyncControlling
    private let clipboard: SecureClipboardWriting
    private let authorizer: PasswordVaultAuthorizing
    private let pasteService: PasteService
    private let storeQueue: DispatchQueue
    private let defaults: UserDefaults
    private let snapshotLock = NSLock()
    private let stateChangeObserverLock = NSLock()
    private let interactiveSensitiveUseLock = NSLock()
    private var snapshot: PasswordVaultViewState
    private var interactiveSensitiveUseObservers = [UUID: () -> Void]()
    private var stateChangeObservers = [UUID: () -> Void]()
    let vaultAgentExecutor: VaultAgentSerialExecutor
    var onChange: (() -> Void)?
    var onInteractiveSensitiveUse: (() -> Void)?

    init(
        store: PasswordVaultStore = KDBXPasswordVaultStore(),
        syncController: PasswordVaultSyncControlling = LocalOnlyPasswordVaultSyncController(),
        clipboard: SecureClipboardWriting = SecureClipboardService(),
        authorizer: PasswordVaultAuthorizing = SystemPasswordVaultAuthorizer(),
        pasteService: PasteService = PasteService(),
        defaults: UserDefaults = .standard,
        storeQueue: DispatchQueue = DispatchQueue(
            label: "com.pastera.password-vault.store",
            qos: .userInitiated
        )
    ) {
        self.store = store
        self.syncController = syncController
        self.clipboard = clipboard
        self.authorizer = authorizer
        self.pasteService = pasteService
        self.defaults = defaults
        self.storeQueue = storeQueue
        vaultAgentExecutor = VaultAgentSerialExecutor(queue: storeQueue)
        snapshot = PasswordVaultViewState(state: .locked)
        store.bindSessionExecutor(vaultAgentExecutor) { [weak self] in
            self?.storeStateDidChange()
        }
        (store as? PasswordVaultSyncAccess)?.setCommitObserver { [weak syncController] commit in
            syncController?.record(commit)
        }
        vaultAgentExecutor.sync { refreshSnapshotFromStore() }
    }

    var state: PasswordVaultState {
        let snapshot = currentSnapshot
        return snapshot.isBusy ? .unlocking : snapshot.state
    }
    var agentVaultReady: Bool {
        let value = state
        return value == .unlocked || value.isReadableWarning
    }
    var viewState: PasswordVaultViewState { currentSnapshot }

    func folders() throws -> [PasswordVaultFolder] { currentSnapshot.folders }
    func entries() throws -> [PasswordVaultEntry] { currentSnapshot.entries }

    func checkQuickUnlockAvailability(completion: @escaping (Bool) -> Void) {
        storeQueue.async { [weak self] in
            guard let self else { return }
            let isAvailable = self.store.canQuickUnlock
            DispatchQueue.main.async { completion(isAvailable) }
        }
    }

    func loadSecuritySettings(completion: @escaping (PasswordVaultSecuritySettingsState) -> Void) {
        vaultAgentExecutor.async { [weak self] in
            guard let self else { return }
            let snapshot = self.currentSnapshot
            let state = PasswordVaultSecuritySettingsState(
                vaultState: snapshot.state,
                isBusy: snapshot.isBusy,
                autoLockInterval: VaultSessionController.resolvedTimeout(defaults: self.defaults),
                quickUnlockEnabled: self.quickUnlockIntent,
                quickUnlockAvailable: self.store.canQuickUnlock
            )
            DispatchQueue.main.async { completion(state) }
        }
    }

    func setAutoLockInterval(
        _ interval: TimeInterval,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        perform(completion: completion) {
            guard VaultSessionController.allowedTimeouts.contains(interval) else {
                throw PasswordVaultError.invalidAutoLockInterval
            }
            self.defaults.set(interval, forKey: Constants.UserDefaults.passwordVaultAutoLockInterval)
            self.store.refreshAutoLockSchedule()
        }
    }

    func setQuickUnlockEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        perform(completion: completion) {
            if enabled {
                try self.store.enableQuickUnlock()
            } else {
                try self.store.disableQuickUnlock()
            }
            self.defaults.set(enabled, forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled)
        }
    }

    // swiftlint:disable:next inclusive_language
    func changeMasterPassword(
        currentPassword: String,
        newPassword: String,
        completion: @escaping (Result<PasswordVaultMasterPasswordChangeResult, PasswordVaultError>) -> Void
    ) {
        perform(completion: completion) {
            let result = try self.store.changeMasterPassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                keepQuickUnlockEnabled: self.quickUnlockIntent
            )
            if result.warnings.contains(.quickUnlockDisabled) {
                self.defaults.set(false, forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled)
            }
            return result
        }
    }

    @discardableResult
    func addStateChangeObserver(_ observer: @escaping () -> Void) -> UUID {
        let identifier = UUID()
        stateChangeObserverLock.lock()
        stateChangeObservers[identifier] = observer
        stateChangeObserverLock.unlock()
        return identifier
    }

    func removeStateChangeObserver(_ identifier: UUID) {
        stateChangeObserverLock.lock()
        stateChangeObservers.removeValue(forKey: identifier)
        stateChangeObserverLock.unlock()
    }

    func createDatabase(
        masterPassword: String, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        performLifecycle(completion: completion) {
            try self.store.createDatabase(masterPassword: masterPassword, rememberQuickUnlock: self.quickUnlockIntent)
        }
    }

    func unlock(
        masterPassword: String, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        performLifecycle(completion: completion) {
            try self.store.unlock(masterPassword: masterPassword, rememberQuickUnlock: self.quickUnlockIntent)
        }
    }

    func unlockWithQuickKey(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        performLifecycle(completion: completion) {
            try self.store.unlockWithQuickKey(reason: String(localized: "Authenticate to unlock the password database."))
        }
    }
    func createFolder(name: String, completion: @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.createFolder(name: name) }
    }

    func renameFolder(id: UUID, name: String, completion: @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.renameFolder(id: id, name: name) }
    }

    func deleteFolder(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        let confirmedEntryIDs = Set(currentSnapshot.entries.filter { $0.folderID == id }.map(\.id))
        authorize(
            reason: String(localized: "Authenticate to delete this folder and its passwords."),
            recordsInteractiveSensitiveUse: true,
            completion: completion
        ) {
            let currentEntryIDs = Set(try self.store.listEntries().filter { $0.folderID == id }.map(\.id))
            guard currentEntryIDs == confirmedEntryIDs else { throw PasswordVaultError.externalConflict }
            try self.store.deleteFolder(id: id)
        }
    }

    func moveEntry(id: UUID, to folderID: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.moveEntry(id: id, to: folderID) }
    }

    func reorderFolders(_ folderIDs: [UUID], completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.reorderFolders(folderIDs) }
    }

    func moveEntry(
        id: UUID,
        to folderID: UUID,
        orderedEntryIDsByFolder: [UUID: [UUID]],
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        perform(completion: completion) {
            try self.store.moveEntry(
                id: id,
                to: folderID,
                orderedEntryIDsByFolder: orderedEntryIDsByFolder
            )
        }
    }

    private func performLifecycle(
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void,
        operation: @escaping () throws -> Void
    ) {
        publishBusyState()
        storeQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<Void, PasswordVaultError>
            do {
                try operation()
                result = .success(())
            } catch let error as PasswordVaultError {
                result = .failure(error)
            } catch {
                result = .failure(.corruptedData)
            }
            if case .success = result,
               self.store.state == .unlocked || self.store.state.isReadableWarning {
                self.syncController.synchronize(reason: .localChange)
            }
            self.finish(result, completion: completion)
        }
    }

    func createEntry(_ draft: PasswordVaultDraft, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(
            reason: String(localized: "Authenticate to save this password."),
            recordsInteractiveSensitiveUse: true,
            completion: completion
        ) {
            _ = try self.store.create(draft)
        }
    }

    func loadDraft(id: UUID, completion: @escaping (Result<PasswordVaultDraft, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to view or edit this password."), completion: completion) {
            guard let entry = try self.store.listEntries().first(where: { $0.id == id }) else {
                throw PasswordVaultError.entryNotFound
            }
            let password = try self.store.revealPassword(
                id: id,
                reason: String(localized: "Authenticate to view or edit this password.")
            )
            return PasswordVaultDraft(
                folderID: entry.folderID,
                title: entry.title,
                website: entry.website,
                username: entry.username,
                note: entry.note,
                password: password
            )
        }
    }

    func updateEntry(id: UUID, draft: PasswordVaultDraft, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(
            reason: String(localized: "Authenticate to save this password."),
            recordsInteractiveSensitiveUse: true,
            completion: completion
        ) {
            _ = try self.store.update(id: id, draft: draft)
        }
    }

    func copyPassword(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(
            reason: String(localized: "Authenticate to copy this password."),
            recordsInteractiveSensitiveUse: true,
            completion: completion
        ) {
            let password = try self.store.revealPassword(
                id: id,
                reason: String(localized: "Authenticate to copy this password.")
            )
            self.clipboard.copySecret(password, clearAfter: .seconds(60))
        }
    }

    func pasteUsername(id: UUID, targetContext: PasteTargetContext?, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(recordsInteractiveSensitiveUse: true, completion: completion) {
            guard let entry = try self.store.listEntries().first(where: { $0.id == id }) else {
                throw PasswordVaultError.entryNotFound
            }
            guard !entry.username.isEmpty else { throw PasswordVaultError.invalidUsername }
            DispatchQueue.main.async { self.pasteService.pasteText(entry.username, restoring: targetContext) }
        }
    }

    func pastePassword(id: UUID, targetContext: PasteTargetContext?, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(
            reason: String(localized: "Authenticate to paste this password."),
            recordsInteractiveSensitiveUse: true,
            completion: completion
        ) {
            let password = try self.store.revealPassword(id: id, reason: String(localized: "Authenticate to paste this password."))
            self.clipboard.copySecret(password, clearAfter: .seconds(60))
            DispatchQueue.main.async { self.pasteService.paste(restoring: targetContext) }
        }
    }

    func deleteEntry(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(
            reason: String(localized: "Authenticate to delete this password."),
            recordsInteractiveSensitiveUse: true,
            completion: completion
        ) {
            try self.store.delete(id: id, reason: String(localized: "Authenticate to delete this password."))
        }
    }

    private func authorize<T>(
        reason: String,
        recordsInteractiveSensitiveUse: Bool = false,
        completion: @escaping (Result<T, PasswordVaultError>) -> Void,
        operation: @escaping () throws -> T
    ) {
        authorizer.authorize(reason: reason) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.perform(
                    recordsInteractiveSensitiveUse: recordsInteractiveSensitiveUse,
                    completion: completion,
                    operation: operation
                )
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func perform<T>(
        recordsInteractiveSensitiveUse: Bool = false,
        completion: @escaping (Result<T, PasswordVaultError>) -> Void,
        operation: @escaping () throws -> T
    ) {
        publishBusyState()
        storeQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<T, PasswordVaultError>
            do {
                result = .success(try operation())
                if recordsInteractiveSensitiveUse {
                    self.notifyInteractiveSensitiveUse()
                }
            } catch let error as PasswordVaultError {
                result = .failure(error)
            } catch {
                result = .failure(.keychainUnavailable)
            }
            self.finish(result, completion: completion)
        }
    }

    func ensureReadyForAgent(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        performForAgent(refreshSnapshot: true, completion: completion) {
            if self.store.state == .unlocked || self.store.state.isReadableWarning {
                return
            }
            try self.store.unlockForAutomation()
        }
    }

    func agentMetadata(
        completion: @escaping (Result<([PasswordVaultFolder], [PasswordVaultEntry]), PasswordVaultError>) -> Void
    ) {
        performForAgent(completion: completion) {
            (try self.store.listFolders(), try self.store.listEntries())
        }
    }

    func agentPaste(
        entryID: UUID,
        field: VaultAgentSecretField,
        target: PasteTargetContext,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        performForAgent(completion: completion) {
            switch field {
            case .username:
                guard let entry = try self.store.listEntries().first(where: { $0.id == entryID }) else {
                    throw PasswordVaultError.entryNotFound
                }
                guard !entry.username.isEmpty else { throw PasswordVaultError.invalidUsername }
                DispatchQueue.main.async {
                    self.pasteService.pasteText(entry.username, restoring: target)
                }
            case .password:
                let password = try self.store.revealPassword(id: entryID, reason: "Pastera Agent password paste")
                self.clipboard.copySecret(password, clearAfter: .seconds(60))
                DispatchQueue.main.async {
                    self.pasteService.paste(restoring: target)
                }
            }
        }
    }

    func agentSecret(
        entryID: UUID,
        field: VaultAgentSecretField,
        completion: @escaping (Result<Data, PasswordVaultError>) -> Void
    ) {
        performForAgent(completion: completion) {
            switch field {
            case .username:
                guard let entry = try self.store.listEntries().first(where: { $0.id == entryID }) else {
                    throw PasswordVaultError.entryNotFound
                }
                return Data(entry.username.utf8)
            case .password:
                return Data(try self.store.revealPassword(
                    id: entryID,
                    reason: "Pastera Agent password delivery"
                ).utf8)
            }
        }
    }

    func agentCopy(
        entryID: UUID,
        field: VaultAgentSecretField,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        performForAgent(completion: completion) {
            let value: String
            switch field {
            case .username:
                guard let entry = try self.store.listEntries().first(where: { $0.id == entryID }) else {
                    throw PasswordVaultError.entryNotFound
                }
                value = entry.username
            case .password:
                value = try self.store.revealPassword(
                    id: entryID,
                    reason: "Pastera Agent password copy"
                )
            }
            self.clipboard.copySecret(value, clearAfter: .seconds(60))
        }
    }

    func enableAutomationUnlockForAgent() throws {
        try vaultAgentExecutor.sync { try store.enableAutomationUnlock() }
    }

    func disableAutomationUnlockForAgent() throws {
        try vaultAgentExecutor.sync { try store.disableAutomationUnlock() }
    }

    private func performForAgent<T>(
        refreshSnapshot: Bool = false,
        completion: @escaping (Result<T, PasswordVaultError>) -> Void,
        operation: @escaping () throws -> T
    ) {
        vaultAgentExecutor.async { [weak self] in
            guard let self else { return }
            let result: Result<T, PasswordVaultError>
            do {
                result = .success(try operation())
            } catch let error as PasswordVaultError {
                result = .failure(error)
            } catch {
                result = .failure(.keychainUnavailable)
            }
            if refreshSnapshot {
                let error: PasswordVaultError?
                if case let .failure(value) = result { error = value } else { error = nil }
                self.refreshSnapshotFromStore(error: error)
            }
            DispatchQueue.main.async { [weak self] in
                if refreshSnapshot {
                    self?.notifyStateChange()
                }
                completion(result)
            }
        }
    }

    private var currentSnapshot: PasswordVaultViewState {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshot
    }

    private func publishBusyState() {
        let current = currentSnapshot
        setSnapshot(PasswordVaultViewState(
            state: .unlocking,
            folders: current.folders,
            entries: current.entries,
            isBusy: true,
            error: nil
        ))
        DispatchQueue.main.async { [weak self] in self?.notifyStateChange() }
    }

    private func refreshSnapshotFromStore(error: PasswordVaultError? = nil) {
        let state = store.state
        let folders = (state == .unlocked || state.isReadableWarning) ? (try? store.listFolders()) ?? [] : []
        let entries = (state == .unlocked || state.isReadableWarning) ? (try? store.listEntries()) ?? [] : []
        setSnapshot(.init(state: state, folders: folders, entries: entries, isBusy: false, error: error))
    }

    private func storeStateDidChange() {
        refreshSnapshotFromStore()
        DispatchQueue.main.async { [weak self] in self?.notifyStateChange() }
    }

    private func setSnapshot(_ value: PasswordVaultViewState) {
        snapshotLock.lock()
        snapshot = value
        snapshotLock.unlock()
    }

    private func finish<T>(
        _ result: Result<T, PasswordVaultError>,
        completion: @escaping (Result<T, PasswordVaultError>) -> Void
    ) {
        let error: PasswordVaultError?
        if case let .failure(value) = result { error = value } else { error = nil }
        refreshSnapshotFromStore(error: error)
        DispatchQueue.main.async { [weak self] in
            self?.notifyStateChange()
            completion(result)
        }
    }

    private var quickUnlockIntent: Bool {
        let key = Constants.UserDefaults.passwordVaultQuickUnlockEnabled
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    private func notifyStateChange() {
        onChange?()
        stateChangeObserverLock.lock()
        let observers = Array(stateChangeObservers.values)
        stateChangeObserverLock.unlock()
        observers.forEach { $0() }
    }
}

extension PasswordVaultUIController {
    var sensitiveObserverCountForTesting: Int {
        interactiveSensitiveUseLock.lock()
        defer { interactiveSensitiveUseLock.unlock() }
        return interactiveSensitiveUseObservers.count
    }

    @discardableResult
    func addInteractiveSensitiveUseObserver(_ observer: @escaping () -> Void) -> UUID {
        let identifier = UUID()
        interactiveSensitiveUseLock.lock()
        interactiveSensitiveUseObservers[identifier] = observer
        interactiveSensitiveUseLock.unlock()
        return identifier
    }

    func removeInteractiveSensitiveUseObserver(_ identifier: UUID) {
        interactiveSensitiveUseLock.lock()
        interactiveSensitiveUseObservers.removeValue(forKey: identifier)
        interactiveSensitiveUseLock.unlock()
    }

    private func notifyInteractiveSensitiveUse() {
        interactiveSensitiveUseLock.lock()
        let observers = Array(interactiveSensitiveUseObservers.values)
        interactiveSensitiveUseLock.unlock()
        onInteractiveSensitiveUse?()
        observers.forEach { $0() }
    }
}

private extension PasswordVaultState {
    var isReadableWarning: Bool {
        if case .readOnlyWarning = self { return true }
        return false
    }
}
