//
//  MainMenuPanelController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/03.
//
//  Copyright © 2015-2026 Clipy Project.
import Cocoa
import KeyHolder
import Magnet

// swiftlint:disable file_length

enum MainMenuPanelLayout {
    static let width: CGFloat = 300
    static let fixedHeight: CGFloat = 356
    static let topInset: CGFloat = 10
    static let bottomInset: CGFloat = 10
    static let rowHeight: CGFloat = 32
    static let compactImageRowHeight: CGFloat = 32
    static let snippetFolderRowHeight: CGFloat = 32
    static let noticeHeight: CGFloat = 52
    static let headerHeight: CGFloat = 38
    static let toolbarHeight: CGFloat = 40
    static let searchHeight: CGFloat = 28
    static let searchToolbarGap: CGFloat = 8
    static let sectionInset: CGFloat = 8
    static let sectionGap: CGFloat = 4
    static let sectionRadius: CGFloat = 12
    static let contentInnerPadding: CGFloat = 3
    static let inlineEditorHeight: CGFloat = 210
    static let folderShortcutEditorHeight: CGFloat = 38
    static let separatorHeight: CGFloat = 1
    static let separatorHorizontalInset: CGFloat = 8
    static let separatorVerticalInset: CGFloat = 3
    static let separatorAlpha: CGFloat = 0.10
    static let oneDriveStatusButtonSize: CGFloat = 28
    static let oneDriveStatusIconSize: CGFloat = 14
    static let oneDriveStatusTrailingInset: CGFloat = 7
    static let toolbarButtonSize: CGFloat = 30
    static let toolbarHorizontalInset: CGFloat = 8
    static let modeButtonWidth: CGFloat = 31
    static let modeControlHeight: CGFloat = 28
    static let cornerRadius: CGFloat = PasteraDesignTokens.Metrics.panelCornerRadius
    static let screenPadding: CGFloat = 8
    static let folderHoverOpenDelay: TimeInterval = 0.45
}

enum MainMenuVisualColors {
    static let panelBackground = NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.135, alpha: 1.0)
    static let panelBorder = NSColor(calibratedWhite: 1.0, alpha: 0.06)
    static let sectionSurface = NSColor(calibratedWhite: 1.0, alpha: 0.036)
    static let headerSurface = NSColor(calibratedWhite: 1.0, alpha: 0.050)
    static let contentSurface = NSColor(calibratedWhite: 1.0, alpha: 0.035)
    static let footerSurface = NSColor(calibratedWhite: 1.0, alpha: 0.040)
    static let sectionBorder = NSColor(calibratedWhite: 1.0, alpha: 0.070)
    static let toolbarSurface = NSColor(calibratedWhite: 1.0, alpha: 0.050)
    static let controlSurface = NSColor(calibratedWhite: 1.0, alpha: 0.052)
    static let controlBorder = NSColor(calibratedWhite: 1.0, alpha: 0.085)
    static let hoveredRow = NSColor(calibratedWhite: 1.0, alpha: 0.060)
    static let selectedRow = NSColor(calibratedWhite: 1.0, alpha: 0.105)
    static let accentFill = NSColor.controlAccentColor.withAlphaComponent(0.16)
    static let separator = NSColor(calibratedWhite: 1.0, alpha: 0.095)
}

#if DEBUG
struct MainMenuChromeStyle {
    let backgroundAlpha: CGFloat
    let borderWidth: CGFloat
}
#endif

enum MainMenuPanelItem {
    case separator
    case notice(title: String, message: String, image: NSImage?)
    case snippetFolder(title: String, image: NSImage?, shortcutText: String? = nil, onOpen: (NSRect?) -> Void)
    case action(title: String, image: NSImage?, shortcutText: String? = nil, onSelect: () -> Void)
}

struct MainMenuHistoryDataSource {
    typealias StateUpdate = (inout HistoryMenuPaginationState) -> Void
    typealias RowBuilder = (PasteboardHistoryDetail, Int, @escaping () -> Void) -> HistoryMenuRowView

    let currentState: () -> HistoryMenuPaginationState
    let updateState: (StateUpdate) -> Void
    let fetchPage: () -> HistoryMenuPage
    let makeRowView: RowBuilder
    let selectHistory: (PasteboardHistory.ID, PasteTargetContext?) -> Void
    let fetchEditableText: (PasteboardHistory.ID) -> String?
    let updateTextHistory: (PasteboardHistory.ID, String) -> Bool

    init(
        currentState: @escaping () -> HistoryMenuPaginationState,
        updateState: @escaping (StateUpdate) -> Void,
        fetchPage: @escaping () -> HistoryMenuPage,
        makeRowView: @escaping RowBuilder,
        selectHistory: @escaping (PasteboardHistory.ID, PasteTargetContext?) -> Void,
        fetchEditableText: @escaping (PasteboardHistory.ID) -> String? = { _ in nil },
        updateTextHistory: @escaping (PasteboardHistory.ID, String) -> Bool = { _, _ in false }
    ) {
        self.currentState = currentState
        self.updateState = updateState
        self.fetchPage = fetchPage
        self.makeRowView = makeRowView
        self.selectHistory = selectHistory
        self.fetchEditableText = fetchEditableText
        self.updateTextHistory = updateTextHistory
    }
}

struct MainMenuSnippetDataSource {
    let fetchFolderDetails: () -> [SnippetFolderDetail]
    let fetchFolderDetail: (SnippetFolder.ID) -> SnippetFolderDetail?
    let selectSnippet: (Snippet.ID, PasteTargetContext?) -> Void
    let createFolder: (String) -> SnippetFolder?
    let createSnippet: (SnippetFolder.ID, String, String) -> Snippet?
    let updateFolderTitle: (SnippetFolder.ID, String) -> Bool
    let updateSnippetTitle: (Snippet.ID, String) -> Void
    let updateSnippetContent: (Snippet.ID, String) -> Bool
    let deleteFolder: (SnippetFolder.ID) -> Void
    let deleteSnippet: (Snippet.ID) -> Void
    let reorderFolders: ([SnippetFolder.ID]) -> Bool
    let moveSnippet: (Snippet.ID, SnippetFolder.ID, [SnippetFolder.ID: [Snippet.ID]]) -> Bool
    let folderKeyCombo: (SnippetFolder.ID) -> KeyCombo?
    let updateFolderKeyCombo: (SnippetFolder.ID, KeyCombo) -> Void
    let clearFolderKeyCombo: (SnippetFolder.ID) -> Void

    init(
        fetchFolderDetails: @escaping () -> [SnippetFolderDetail],
        fetchFolderDetail: @escaping (SnippetFolder.ID) -> SnippetFolderDetail?,
        selectSnippet: @escaping (Snippet.ID, PasteTargetContext?) -> Void,
        createFolder: @escaping (String) -> SnippetFolder? = { _ in nil },
        createSnippet: @escaping (SnippetFolder.ID, String, String) -> Snippet? = { _, _, _ in nil },
        updateFolderTitle: @escaping (SnippetFolder.ID, String) -> Bool = { _, _ in false },
        updateSnippetTitle: @escaping (Snippet.ID, String) -> Void = { _, _ in },
        updateSnippetContent: @escaping (Snippet.ID, String) -> Bool = { _, _ in false },
        deleteFolder: @escaping (SnippetFolder.ID) -> Void = { _ in },
        deleteSnippet: @escaping (Snippet.ID) -> Void = { _ in },
        reorderFolders: @escaping ([SnippetFolder.ID]) -> Bool = { _ in false },
        moveSnippet: @escaping (Snippet.ID, SnippetFolder.ID, [SnippetFolder.ID: [Snippet.ID]]) -> Bool = { _, _, _ in false },
        folderKeyCombo: @escaping (SnippetFolder.ID) -> KeyCombo? = { _ in nil },
        updateFolderKeyCombo: @escaping (SnippetFolder.ID, KeyCombo) -> Void = { _, _ in },
        clearFolderKeyCombo: @escaping (SnippetFolder.ID) -> Void = { _ in }
    ) {
        self.fetchFolderDetails = fetchFolderDetails
        self.fetchFolderDetail = fetchFolderDetail
        self.selectSnippet = selectSnippet
        self.createFolder = createFolder
        self.createSnippet = createSnippet
        self.updateFolderTitle = updateFolderTitle
        self.updateSnippetTitle = updateSnippetTitle
        self.updateSnippetContent = updateSnippetContent
        self.deleteFolder = deleteFolder
        self.deleteSnippet = deleteSnippet
        self.reorderFolders = reorderFolders
        self.moveSnippet = moveSnippet
        self.folderKeyCombo = folderKeyCombo
        self.updateFolderKeyCombo = updateFolderKeyCombo
        self.clearFolderKeyCombo = clearFolderKeyCombo
    }
}

struct MainMenuPasswordVaultDataSource {
    let state: () -> PasswordVaultState
    let checkQuickUnlockAvailability: (@escaping (Bool) -> Void) -> Void
    let createDatabase: (String, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let unlock: (String, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let unlockWithQuickKey: (@escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let retryLocalPreparation: () -> Void
    let fetchFolders: () throws -> [PasswordVaultFolder]
    let fetchEntries: () throws -> [PasswordVaultEntry]
    let copyPassword: (PasswordVaultEntry.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let pasteUsername: (PasswordVaultEntry.ID, PasteTargetContext?, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let pastePassword: (PasswordVaultEntry.ID, PasteTargetContext?, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let loadDraft: (PasswordVaultEntry.ID, @escaping (Result<PasswordVaultDraft, PasswordVaultError>) -> Void) -> Void
    let createEntry: (PasswordVaultDraft, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let updateEntry: (PasswordVaultEntry.ID, PasswordVaultDraft, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let deleteEntry: (PasswordVaultEntry.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let createFolder: (String, @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) -> Void
    let renameFolder: (PasswordVaultFolder.ID, String, @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) -> Void
    let deleteFolder: (PasswordVaultFolder.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let reorderFolders: ([PasswordVaultFolder.ID], @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void
    let moveEntry: (PasswordVaultEntry.ID, PasswordVaultFolder.ID, [PasswordVaultFolder.ID: [PasswordVaultEntry.ID]], @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void

    init(
        state: @escaping () -> PasswordVaultState = { .unlocked },
        checkQuickUnlockAvailability: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
            completion(false)
        },
        createDatabase: @escaping (String, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, completion in completion(.failure(.databaseNotConfigured)) },
        unlock: @escaping (String, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, completion in completion(.failure(.vaultLocked)) },
        unlockWithQuickKey: @escaping (@escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { completion in completion(.failure(.keychainUnavailable)) },
        retryLocalPreparation: @escaping () -> Void = {},
        fetchFolders: @escaping () throws -> [PasswordVaultFolder],
        fetchEntries: @escaping () throws -> [PasswordVaultEntry],
        copyPassword: @escaping (PasswordVaultEntry.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void,
        pasteUsername: @escaping (PasswordVaultEntry.ID, PasteTargetContext?, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, _, completion in completion(.failure(.entryNotFound)) },
        pastePassword: @escaping (PasswordVaultEntry.ID, PasteTargetContext?, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, _, completion in completion(.failure(.entryNotFound)) },
        loadDraft: @escaping (PasswordVaultEntry.ID, @escaping (Result<PasswordVaultDraft, PasswordVaultError>) -> Void) -> Void,
        createEntry: @escaping (PasswordVaultDraft, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void,
        updateEntry: @escaping (PasswordVaultEntry.ID, PasswordVaultDraft, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void,
        deleteEntry: @escaping (PasswordVaultEntry.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void,
        createFolder: @escaping (String) throws -> PasswordVaultFolder,
        renameFolder: @escaping (PasswordVaultFolder.ID, String) throws -> PasswordVaultFolder,
        deleteFolder: @escaping (PasswordVaultFolder.ID) throws -> Void,
        createFolderAsync: ((String, @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) -> Void)? = nil,
        renameFolderAsync: ((PasswordVaultFolder.ID, String, @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) -> Void)? = nil,
        deleteFolderAsync: ((PasswordVaultFolder.ID, @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void)? = nil,
        reorderFolders: @escaping ([PasswordVaultFolder.ID], @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, completion in completion(.failure(.saveFailed)) },
        moveEntry: @escaping (PasswordVaultEntry.ID, PasswordVaultFolder.ID, [PasswordVaultFolder.ID: [PasswordVaultEntry.ID]], @escaping (Result<Void, PasswordVaultError>) -> Void) -> Void = { _, _, _, completion in completion(.failure(.saveFailed)) }
    ) {
        self.state = state
        self.checkQuickUnlockAvailability = checkQuickUnlockAvailability
        self.createDatabase = createDatabase
        self.unlock = unlock
        self.unlockWithQuickKey = unlockWithQuickKey
        self.retryLocalPreparation = retryLocalPreparation
        self.fetchFolders = fetchFolders
        self.fetchEntries = fetchEntries
        self.copyPassword = copyPassword
        self.pasteUsername = pasteUsername
        self.pastePassword = pastePassword
        self.loadDraft = loadDraft
        self.createEntry = createEntry
        self.updateEntry = updateEntry
        self.deleteEntry = deleteEntry
        self.createFolder = createFolderAsync ?? { name, completion in
            do { completion(.success(try createFolder(name))) }
            catch let error as PasswordVaultError { completion(.failure(error)) }
            catch { completion(.failure(.saveFailed)) }
        }
        self.renameFolder = renameFolderAsync ?? { id, name, completion in
            do { completion(.success(try renameFolder(id, name))) }
            catch let error as PasswordVaultError { completion(.failure(error)) }
            catch { completion(.failure(.saveFailed)) }
        }
        self.deleteFolder = deleteFolderAsync ?? { id, completion in
            do { try deleteFolder(id); completion(.success(())) }
            catch let error as PasswordVaultError { completion(.failure(error)) }
            catch { completion(.failure(.saveFailed)) }
        }
        self.reorderFolders = reorderFolders
        self.moveEntry = moveEntry
    }
}

private final class MainMenuPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class MainMenuPanelController: NSObject, NSWindowDelegate, NSSearchFieldDelegate {
    private enum PasswordVaultQuickUnlockAvailability {
        case unknown
        case checking
        case available
        case unavailable
    }
    private enum DisplayMode {
        case history
        case snippets
        case passwordVault
    }

    private enum PasswordVaultPage: Equatable {
        case vault
        case remoteCredentials
        case conflictSummary
        case localCopyRecovery
    }

    fileprivate enum KeyboardEntryRole {
        case none
        case snippetFolder(SnippetFolder.ID)
        case snippet(Snippet.ID)
        case passwordEntry(PasswordVaultEntry.ID)
    }

    private enum InlineEditorState {
        case history(PasteboardHistory.ID, originalText: String, draftText: String, error: String?)
        case snippetFolder(SnippetFolder.ID, originalTitle: String, draftTitle: String, error: String?)
        case newSnippetFolder(draftTitle: String, error: String?)
        case newSnippet(SnippetFolder.ID, draftTitle: String, draftContent: String, error: String?)
        case snippet(
            Snippet.ID,
            originalTitle: String,
            originalContent: String,
            draftTitle: String,
            draftContent: String,
            error: String?
        )
    }

    private struct KeyboardEntry {
        let title: String
        let role: KeyboardEntryRole
        let view: () -> NSView?
        let setSelected: (Bool) -> Void
        let openChildPanel: (() -> Void)?
        let confirm: () -> Void
    }

    private struct EmbeddedContent {
        let headerTitle: String
        let headerSubtitle: String?
        let showsBackButton: Bool
        let canGoToPreviousPage: Bool
        let canGoToNextPage: Bool
        let typeFilter: HistoryMenuTypeFilter?
        let rows: [EmbeddedRow]
    }

    private struct EmbeddedRow {
        let title: String
        let view: NSView
        let confirm: () -> Void
        let role: KeyboardEntryRole
        let participatesInNavigation: Bool

        init(
            title: String,
            view: NSView,
            confirm: @escaping () -> Void,
            role: KeyboardEntryRole = .none,
            participatesInNavigation: Bool = true
        ) {
            self.title = title
            self.view = view
            self.confirm = confirm
            self.role = role
            self.participatesInNavigation = participatesInNavigation
        }
    }

    private struct EmbeddedRenderItem {
        let view: NSView
        let height: CGFloat
        let row: EmbeddedRow?
    }

    private enum PasswordVaultEditorState {
        case create(PasswordVaultDraft, step: PasswordVaultEditorStep, error: String?)
        case edit(PasswordVaultEntry.ID, PasswordVaultDraft, step: PasswordVaultEditorStep, error: String?)
    }

    private enum PasswordVaultFolderEditorState {
        case create(draftName: String, error: String?)
        case rename(PasswordVaultFolder, draftName: String, error: String?)
    }

    private enum PasswordVaultPendingDeletion: Equatable {
        case folder(PasswordVaultFolder.ID)
        case entry(PasswordVaultEntry.ID)
    }

    private let historyTitle: String
    private let historyImage: NSImage?
    private let historyShortcutText: String?
    private let snippetTitle: String
    private let snippetImage: NSImage?
    private let itemsProvider: () -> [MainMenuPanelItem]
    private let onOpenHistory: () -> Void
    private let onOpenSnippets: () -> Void
    private let historyDataSource: MainMenuHistoryDataSource?
    private let snippetDataSource: MainMenuSnippetDataSource?
    private let passwordVaultDataSource: MainMenuPasswordVaultDataSource?
    private let passwordVaultSyncDataSource: MainMenuPasswordVaultSyncDataSource?
    private let oneDriveStatusService: OneDriveProcessStatusServicing
    private let onOpenPreferences: () -> Void
    private let onOpenOneDriveStatus: () -> Void
    private let onCloseChildPanels: () -> Void
    private var deleteConfirmationRunner: (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult = {
        PasteraConfirmationController.runModal(options: $0, sourceWindow: $1)
    }

    private let contentView = NSView()
    private let searchField = NSSearchField()
    private var panel: MainMenuPanel?
    private var keyboardEntries = [KeyboardEntry]()
    private var selectedKeyboardEntryIndex: Int?
    private var isPinned = true
    private var selectedMode: DisplayMode = .history
    private var expandedSnippetFolderID: SnippetFolder.ID?
    private var isWorkspaceEditing = false
    private var inlineEditorState: InlineEditorState?
    private var inlineEditorView: MainMenuInlineEditorView?
    private var editingFolderShortcutID: SnippetFolder.ID?
    private var folderShortcutEditorView: MainMenuFolderShortcutEditorView?
    private var snippetSearchQuery = ""
    private var passwordVaultSearchQuery = ""
    private var expandedPasswordVaultFolderID: PasswordVaultFolder.ID?
    private var passwordVaultEditorState: PasswordVaultEditorState?
    private var passwordVaultStepEditorView: PasswordVaultStepEditorView?
    private var passwordVaultFolderEditorState: PasswordVaultFolderEditorState?
    private weak var passwordVaultFolderEditorView: PasswordVaultFolderEditorView?
    private var passwordVaultStatusMessage: String?
    private var passwordVaultPendingDeletion: PasswordVaultPendingDeletion?
    private var passwordVaultAccessError: String?
    private var passwordVaultAccessView: PasswordVaultAccessView?
    private var passwordVaultInlineActionView: PasswordVaultInlineActionView?
    private var passwordVaultRemoteCredentialsView: PasswordVaultRemoteCredentialsView?
    private var passwordVaultPage: PasswordVaultPage = .vault
    private var passwordVaultCreateStorageMode: PasswordVaultCreateStorageMode = .localOnly
    private var passwordVaultLocalRecoveryShowsWarning = false
    private var passwordVaultAllowsLocalReplacement = false
    private var passwordVaultSuppressesRemotePrompt = false
    private var passwordVaultAccessModeInFlight: PasswordVaultAccessView.Mode?
    private var passwordVaultAutomaticQuickUnlockAttempted = false
    private var passwordVaultQuickUnlockAvailability = PasswordVaultQuickUnlockAvailability.unknown
    private weak var passwordVaultQuickActionsCoachmarkView: PasswordVaultQuickActionsCoachmarkView?
    private var passwordVaultQuickActionsCoachmarkWorkItem: DispatchWorkItem?
    private var visibleHistoryIDs = [PasteboardHistory.ID]()
    private var visibleSnippetFolderIDs = [SnippetFolder.ID]()
    private var visibleSnippetIDs = [Snippet.ID]()
    private var visiblePasswordVaultFolderIDs = [PasswordVaultFolder.ID]()
    private var visiblePasswordVaultEntryIDs = [PasswordVaultEntry.ID]()
    private var visibleMainMenuRowTitles = [String]()
    private var currentSnippetFolderTitle: String?
    private var isSearchVisible = false
    private var searchQueryChangeTimer: Timer?
    private let searchQueryDebounceInterval: TimeInterval = 0.12
#if DEBUG
    var mainMenuSearchMarkedTextStateProviderForTesting: (() -> Bool)?
#endif
    private var keepsVisibleWhileChildPanelOpen = false
    private var pasteTargetContext: PasteTargetContext?
    private weak var oneDriveStatusButton: MainMenuOneDriveStatusButton?
    private var ocrActivity: PasteboardHistoryOCRActivity = .idle
    private var ocrActivityObserver: NSObjectProtocol?

    private var usesEmbeddedContent: Bool {
        historyDataSource != nil || snippetDataSource != nil || passwordVaultDataSource != nil
    }

    init(
        historyTitle: String,
        historyImage: NSImage?,
        historyShortcutText: String? = nil,
        snippetTitle: String,
        snippetImage: NSImage?,
        itemsProvider: @escaping () -> [MainMenuPanelItem],
        onOpenHistory: @escaping () -> Void,
        onOpenSnippets: @escaping () -> Void,
        historyDataSource: MainMenuHistoryDataSource? = nil,
        snippetDataSource: MainMenuSnippetDataSource? = nil,
        passwordVaultDataSource: MainMenuPasswordVaultDataSource? = nil,
        passwordVaultSyncDataSource: MainMenuPasswordVaultSyncDataSource? = nil,
        oneDriveStatusService: OneDriveProcessStatusServicing = AppEnvironment.current.oneDriveProcessStatusService,
        onOpenPreferences: @escaping () -> Void = {
            (NSApp.delegate as? AppDelegate)?.showPreferenceWindow()
        },
        onOpenOneDriveStatus: (() -> Void)? = nil,
        onCloseChildPanels: @escaping () -> Void = {}
    ) {
        self.historyTitle = historyTitle
        self.historyImage = historyImage
        self.historyShortcutText = historyShortcutText
        self.snippetTitle = snippetTitle
        self.snippetImage = snippetImage
        self.itemsProvider = itemsProvider
        self.onOpenHistory = onOpenHistory
        self.onOpenSnippets = onOpenSnippets
        self.historyDataSource = historyDataSource
        self.snippetDataSource = snippetDataSource
        self.passwordVaultDataSource = passwordVaultDataSource
        self.passwordVaultSyncDataSource = passwordVaultSyncDataSource
        self.oneDriveStatusService = oneDriveStatusService
        self.onOpenPreferences = onOpenPreferences
        self.onOpenOneDriveStatus = onOpenOneDriveStatus ?? onOpenPreferences
        self.onCloseChildPanels = onCloseChildPanels
        super.init()
        ocrActivityObserver = NotificationCenter.default.addObserver(
            forName: PasteboardHistoryOCRIndexer.activityDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let activity = notification.object as? PasteboardHistoryOCRActivity else { return }
            self?.ocrActivity = activity
            self?.reloadContentIfVisible()
        }
    }

    deinit {
        searchQueryChangeTimer?.invalidate()
        if let ocrActivityObserver { NotificationCenter.default.removeObserver(ocrActivityObserver) }
    }

    func show(at screenPoint: NSPoint, pinned: Bool = false, pasteTargetContext: PasteTargetContext? = nil) {
        isWorkspaceEditing = false
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        isSearchVisible = false
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        if !panel.isVisible || !pinned {
            position(panel, near: screenPoint)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(anchoredTo menuFrame: NSRect, pinned: Bool = true, pasteTargetContext: PasteTargetContext? = nil) {
        isWorkspaceEditing = false
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? self.pasteTargetContext ?? PasteTargetContext.capture()
        isSearchVisible = false
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, anchoredTo: menuFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(attachedToStatusItemFrame statusItemFrame: NSRect, pinned: Bool = false, pasteTargetContext: PasteTargetContext? = nil) {
        isWorkspaceEditing = false
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        isSearchVisible = false
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, attachedToStatusItemFrame: statusItemFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func close() -> Bool {
        guard commitInlineEditorFromCurrentDraft() else { return false }
        preservePasswordVaultEditorDrafts()
        searchQueryChangeTimer?.invalidate()
        searchQueryChangeTimer = nil
        keepsVisibleWhileChildPanelOpen = false
        editingFolderShortcutID = nil
        panel?.orderOut(nil)
        return true
    }

    private func handlePanelCancel() {
        if selectedMode == .passwordVault, passwordVaultPage != .vault {
            returnFromPasswordVaultContextPage()
            return
        }
        if passwordVaultEditorState != nil {
            discardPasswordVaultEditor()
            return
        }
        if passwordVaultFolderEditorState != nil {
            passwordVaultFolderEditorState = nil
            reloadContentKeepingTopLeft()
            return
        }
        if editingFolderShortcutID != nil {
            discardFolderShortcutEditor()
            return
        }
        if inlineEditorState != nil {
            discardInlineEditor()
            return
        }
        if isWorkspaceEditing {
            isWorkspaceEditing = false
            reloadContentKeepingTopLeft()
            return
        }
        _ = close()
    }

    var isVisibleForTesting: Bool {
        panel?.isVisible == true
    }

    var visibleFrame: NSRect? {
        guard panel?.isVisible == true else { return nil }
        return panel?.frame
    }

    func reloadContentIfVisible() {
        guard let panel, panel.isVisible else { return }
        let topLeftPoint = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        reloadContent()
        panel.setFrameTopLeftPoint(topLeftPoint)
    }

    func refreshAppearanceIfVisible() {
        guard panel?.isVisible == true else { return }
        applyVisualFoundation()
    }

    var childPasteTargetContext: PasteTargetContext? {
        pasteTargetContext
    }

#if DEBUG
    var pasteTargetProcessIdentifierForTesting: pid_t? {
        pasteTargetContext?.processIdentifier
    }
#endif

    func openHistoryFromMainMenu() {
        guard usesEmbeddedContent else {
            onOpenHistory()
            return
        }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        resetPasswordVaultAccessPresentation()
        passwordVaultPage = .vault
        selectedMode = .history
        reloadContentIfVisible()
        onCloseChildPanels()
    }

    func openSnippetsFromMainMenu() {
        guard usesEmbeddedContent else {
            onOpenSnippets()
            return
        }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        resetPasswordVaultAccessPresentation()
        passwordVaultPage = .vault
        selectedMode = .snippets
        expandedSnippetFolderID = nil
        reloadContentIfVisible()
        onCloseChildPanels()
    }

    func openSnippetFolderFromMainMenu(_ folderID: SnippetFolder.ID) {
        guard usesEmbeddedContent else {
            onOpenSnippets()
            return
        }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        resetPasswordVaultAccessPresentation()
        passwordVaultPage = .vault
        selectedMode = .snippets
        expandedSnippetFolderID = folderID
        reloadContentIfVisible()
        onCloseChildPanels()
    }

    func openPasswordVaultFromMainMenu() {
        guard passwordVaultDataSource != nil else { return }
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        selectedMode = .passwordVault
        passwordVaultPage = .vault
        if !passwordVaultSuppressesRemotePrompt,
           case .failed(.remoteCredentialsRequired) = passwordVaultSyncDataSource?.snapshot().phase {
            passwordVaultPage = .remoteCredentials
        }
        passwordVaultAccessError = nil
        reloadContentIfVisible()
        onCloseChildPanels()
        DispatchQueue.main.async { [weak self] in
            self?.attemptAutomaticPasswordVaultQuickUnlockIfNeeded()
        }
    }

    private func openLegacyHistoryFromMainMenu() {
        onOpenHistory()
    }

    private func openLegacySnippetsFromMainMenu() {
        onOpenSnippets()
    }

    func beginChildPanelPresentation() {
        keepsVisibleWhileChildPanelOpen = true
        if let panel {
            panel.hidesOnDeactivate = false
        }
    }

    func endChildPanelPresentation() {
        keepsVisibleWhileChildPanelOpen = false
        if let panel {
            applyBehavior(to: panel)
        }
    }
}

extension MainMenuPanelController {
    private func makePanelIfNeeded() -> MainMenuPanel {
        if let panel { return panel }

        let panel = MainMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.fixedHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.handlePanelCancel() }
        panel.onKeyDown = { [weak self] event in self?.handleKeyboardNavigation(event) ?? false }
        panel.delegate = self
        panel.contentView = contentView
        applyBehavior(to: panel)
        self.panel = panel
        return panel
    }

    private func applyBehavior(to panel: MainMenuPanel) {
        let behavior = MainMenuPanelBehavior(isPinned: isPinned)
        panel.level = behavior.level
        panel.collectionBehavior = behavior.collectionBehavior
        panel.hidesOnDeactivate = behavior.hidesOnDeactivate
        panel.isMovableByWindowBackground = behavior.isMovableByWindowBackground
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned, !keepsVisibleWhileChildPanelOpen else { return }
        panel?.orderOut(nil)
    }

    private func applyVisualFoundation() {
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = MainMenuPanelLayout.cornerRadius
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = MainMenuVisualColors.panelBackground
            .withAlphaComponent(CPYWindowAppearance.opacity())
            .cgColor
        contentView.layer?.borderColor = MainMenuVisualColors.panelBorder.cgColor
        contentView.layer?.borderWidth = 0.5
    }

    private func reloadContent() {
        inlineEditorView = nil
        guard usesEmbeddedContent else {
            reloadLegacyContent()
            return
        }
        reloadEmbeddedContent()
    }

    // swiftlint:disable:next function_body_length
    private func reloadLegacyContent() {
        removeContentSubviewsForReload()
        keyboardEntries.removeAll()
        selectedKeyboardEntryIndex = nil
        resetVisibleRows()
        applyVisualFoundation()

        let items = itemsProvider()
        let height = MainMenuPanelLayout.fixedHeight
        applyCurrentContentSize()

        var currentY = height - MainMenuPanelLayout.topInset - MainMenuPanelLayout.headerHeight
        let headerView = MainMenuHeaderItemView(
            title: historyTitle,
            image: historyImage,
            shortcutText: historyShortcutText
        )
        headerView.allowsWindowDrag = true
        headerView.frame = NSRect(x: 0, y: currentY, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.headerHeight)
        headerView.onOpen = { [weak self] in self?.openHistoryFromMainMenu() }
        headerView.onHoverOpen = { [weak self] in self?.openHistoryFromMainMenu() }
        let historyEntryIndex = appendKeyboardEntry(
            title: historyTitle,
            view: headerView,
            openChildPanel: { [weak self] in self?.openHistoryFromMainMenu() },
            confirm: { [weak self] in self?.openHistoryFromMainMenu() }
        )
        headerView.onHoverFocus = { [weak self] in
            self?.selectKeyboardEntry(at: historyEntryIndex, triggerChildPanel: false)
        }
        contentView.addSubview(headerView)

        currentY -= MainMenuPanelLayout.separatorVerticalInset + MainMenuPanelLayout.separatorHeight
        addSeparator(at: currentY)
        currentY -= MainMenuPanelLayout.separatorVerticalInset

        for item in items {
            switch item {
            case .separator:
                currentY -= MainMenuPanelLayout.separatorVerticalInset
                addSeparator(at: currentY)
                currentY -= MainMenuPanelLayout.separatorVerticalInset
            case let .notice(title, message, image):
                currentY -= MainMenuPanelLayout.noticeHeight
                let noticeView = MainMenuPanelNoticeView(title: title, message: message, image: image)
                noticeView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.noticeHeight
                )
                contentView.addSubview(noticeView)
            case let .snippetFolder(title, image, shortcutText, onOpen):
                currentY -= MainMenuPanelLayout.snippetFolderRowHeight
                let rowView = MainMenuPanelRowView(
                    title: title,
                    image: image,
                    shortcutText: shortcutText,
                    rowKind: .snippetFolder,
                    rowHeight: MainMenuPanelLayout.snippetFolderRowHeight,
                    showsChevron: true,
                    onHoverOpen: onOpen,
                    onConfirm: onOpen
                )
                rowView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.snippetFolderRowHeight
                )
                let entryIndex = appendKeyboardEntry(
                    title: title,
                    view: rowView,
                    openChildPanel: { [weak rowView] in onOpen(rowView?.screenFrameForOpening) },
                    confirm: { [weak rowView] in onOpen(rowView?.screenFrameForOpening) }
                )
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
                contentView.addSubview(rowView)
            case let .action(title, image, shortcutText, onSelect):
                currentY -= MainMenuPanelLayout.rowHeight
                let rowView = MainMenuPanelRowView(
                    title: title,
                    image: image,
                    shortcutText: shortcutText,
                    rowKind: .action
                ) { _ in onSelect() }
                rowView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.rowHeight
                )
                let entryIndex = appendKeyboardEntry(
                    title: title,
                    view: rowView,
                    openChildPanel: { [weak self] in self?.onCloseChildPanels() },
                    confirm: onSelect
                )
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
                contentView.addSubview(rowView)
            }
        }

        if isSearchVisible {
            addSearchField(at: fixedSearchY)
        }
        addToolbar(at: fixedToolbarY)
    }

    private func reloadEmbeddedContent() {
        HistoryMenuRowView.hidePreviews()
        inlineEditorView = nil
        folderShortcutEditorView = nil
        removeContentSubviewsForReload()
        keyboardEntries.removeAll()
        selectedKeyboardEntryIndex = nil
        resetVisibleRows()
        applyVisualFoundation()

        let content = makeEmbeddedContent()
        let notices = noticeItems()
        applyCurrentContentSize()

        addEmbeddedHeader(content, frame: headerBlockFrame)
        addEmbeddedViewport(content, notices: notices, frame: contentBlockFrame)
        if let searchFieldFrame {
            addSearchField(frame: searchFieldFrame)
        }
        addToolbar(frame: footerDockFrame)
        addOCRActivityViewIfNeeded()
    }

    private func removeContentSubviewsForReload() {
        contentView.subviews
            .filter { !isSearchVisible || $0 !== searchField }
            .forEach { $0.removeFromSuperview() }
    }

    private var fixedToolbarY: CGFloat {
        MainMenuPanelLayout.bottomInset
    }

    private var fixedSearchY: CGFloat {
        fixedToolbarY + MainMenuPanelLayout.toolbarHeight
    }

    private var searchFieldFrame: NSRect? {
        guard isSearchVisible, usesEmbeddedContent else { return nil }
        return NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: MainMenuPanelLayout.bottomInset,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.searchHeight
        )
    }

    private var searchDrawerHeight: CGFloat {
        guard isSearchVisible, usesEmbeddedContent else { return 0 }
        return MainMenuPanelLayout.searchHeight + MainMenuPanelLayout.searchToolbarGap
    }

    private var mainContentVerticalOffset: CGFloat {
        searchDrawerHeight
    }

    private var currentContentSize: NSSize {
        NSSize(
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.fixedHeight + mainContentVerticalOffset
        )
    }

    private var headerBlockFrame: NSRect {
        NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: mainContentVerticalOffset +
                MainMenuPanelLayout.fixedHeight -
                MainMenuPanelLayout.sectionInset -
                MainMenuPanelLayout.headerHeight,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.headerHeight
        )
    }

    private var footerDockFrame: NSRect {
        return NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: mainContentVerticalOffset + MainMenuPanelLayout.bottomInset,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuPanelLayout.toolbarHeight
        )
    }

    private var contentBlockFrame: NSRect {
        let top = headerBlockFrame.minY - MainMenuPanelLayout.sectionGap
        let bottom = footerDockFrame.maxY + MainMenuPanelLayout.sectionGap + ocrActivityHeight
        return NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: bottom,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: max(0, top - bottom)
        )
    }

    private var ocrActivityHeight: CGFloat {
        ocrActivity == .idle ? 0 : MainMenuOCRActivityView.height + MainMenuPanelLayout.sectionGap
    }

    private func addOCRActivityViewIfNeeded() {
        guard ocrActivity != .idle else { return }
        let view = MainMenuOCRActivityView(frame: NSRect(
            x: MainMenuPanelLayout.sectionInset,
            y: footerDockFrame.maxY + MainMenuPanelLayout.sectionGap,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.sectionInset * 2,
            height: MainMenuOCRActivityView.height
        ))
        view.render(ocrActivity)
        contentView.addSubview(view)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            view.animator().alphaValue = 1
        }
    }

    private func applyCurrentContentSize() {
        let size = currentContentSize
        contentView.frame = NSRect(origin: .zero, size: size)
        panel?.setContentSize(size)
    }

    private func applyCurrentContentSizeKeepingTopLeft() {
        let topLeft = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        applyCurrentContentSize()
        if let topLeft {
            panel?.setFrameTopLeftPoint(topLeft)
        }
    }

    private func addEmbeddedViewport(_ content: EmbeddedContent, notices: [MainMenuPanelItem], frame: NSRect) {
        let surfaceView = MainMenuSurfaceView(
            frame: frame,
            identifier: "mainMenuContentBlock"
        )
        let scrollFrame = surfaceView.bounds.insetBy(
            dx: MainMenuPanelLayout.contentInnerPadding,
            dy: MainMenuPanelLayout.contentInnerPadding
        )
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed

        let renderItems = embeddedRenderItems(content, notices: notices)
        let documentHeight = max(scrollFrame.height, renderItems.reduce(CGFloat(0)) { $0 + $1.height })
        let documentView = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: scrollFrame.width,
            height: documentHeight
        ))
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor.clear.cgColor

        var currentY = documentHeight
        for item in renderItems {
            currentY -= item.height
            item.view.frame = NSRect(x: 0, y: currentY, width: scrollFrame.width, height: item.height)
            documentView.addSubview(item.view)
            guard let row = item.row else { continue }
            guard row.participatesInNavigation else { continue }
            let entryIndex = appendKeyboardEntry(
                title: row.title,
                view: row.view,
                openChildPanel: nil,
                role: row.role,
                confirm: row.confirm
            )
            if let rowView = row.view as? MainMenuPanelRowView {
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
            } else if let rowView = row.view as? MainMenuEmbeddedEmptyRowView {
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
            }
            visibleMainMenuRowTitles.append(row.title)
        }

        scrollView.documentView = documentView
        let topOffset = max(0, documentHeight - scrollFrame.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: topOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        surfaceView.addSubview(scrollView)
        contentView.addSubview(surfaceView)
    }

    private func embeddedRenderItems(
        _ content: EmbeddedContent,
        notices: [MainMenuPanelItem]
    ) -> [EmbeddedRenderItem] {
        var items = [EmbeddedRenderItem]()
        for item in notices {
            switch item {
            case .separator:
                items.append(EmbeddedRenderItem(
                    view: NSView(frame: NSRect(
                        x: 0,
                        y: 0,
                        width: MainMenuPanelLayout.width,
                        height: MainMenuPanelLayout.sectionGap
                    )),
                    height: MainMenuPanelLayout.sectionGap,
                    row: nil
                ))
            case let .notice(title, message, image):
                items.append(EmbeddedRenderItem(
                    view: MainMenuPanelNoticeView(title: title, message: message, image: image),
                    height: MainMenuPanelLayout.noticeHeight,
                    row: nil
                ))
            case .snippetFolder, .action:
                break
            }
        }
        items.append(contentsOf: content.rows.map { row in
            EmbeddedRenderItem(
                view: row.view,
                height: max(row.view.frame.height, MainMenuPanelLayout.rowHeight),
                row: row
            )
        })
        return items
    }

    private func preferredHeight(for items: [MainMenuPanelItem]) -> CGFloat {
        let rowHeights = items.reduce(CGFloat(0)) { total, item in
            switch item {
            case .separator:
                return total + MainMenuPanelLayout.separatorHeight + MainMenuPanelLayout.separatorVerticalInset * 2
            case .notice:
                return total + MainMenuPanelLayout.noticeHeight
            case .snippetFolder:
                return total + MainMenuPanelLayout.snippetFolderRowHeight
            case .action:
                return total + MainMenuPanelLayout.rowHeight
            }
        }
        return MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + rowHeights
            + MainMenuPanelLayout.toolbarHeight
            + (isSearchVisible ? MainMenuPanelLayout.searchHeight : 0)
            + MainMenuPanelLayout.bottomInset
    }

    private func preferredHeight(for content: EmbeddedContent, notices: [MainMenuPanelItem]) -> CGFloat {
        let noticeHeight = notices.reduce(CGFloat(0)) { total, item in
            switch item {
            case .separator:
                return total + MainMenuPanelLayout.separatorHeight + MainMenuPanelLayout.separatorVerticalInset * 2
            case .notice:
                return total + MainMenuPanelLayout.noticeHeight
            case .snippetFolder, .action:
                return total
            }
        }
        let rowsHeight = content.rows.reduce(CGFloat(0)) { total, row in
            total + max(row.view.frame.height, MainMenuPanelLayout.rowHeight)
        }
        return MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + noticeHeight
            + rowsHeight
            + MainMenuPanelLayout.toolbarHeight
            + (isSearchVisible ? MainMenuPanelLayout.searchHeight : 0)
            + MainMenuPanelLayout.bottomInset
    }

    private func makeEmbeddedContent() -> EmbeddedContent {
        switch selectedMode {
        case .history:
            if let inlineEditorState, case .history = inlineEditorState {
                return mergedEditor(makeInlineEditorContent(inlineEditorState), list: makeHistoryContent())
            }
            return makeHistoryContent()
        case .snippets:
            if let inlineEditorState, case .history = inlineEditorState {
                return makeSnippetContent()
            } else if let inlineEditorState, case .newSnippetFolder = inlineEditorState {
                return mergedEditorAtEnd(makeInlineEditorContent(inlineEditorState), list: makeSnippetContent())
            } else if let inlineEditorState,
                      case .snippetFolder = inlineEditorState {
                return makeSnippetContent()
            } else if let inlineEditorState,
                      case .snippet = inlineEditorState {
                return makeSnippetContent()
            } else if let inlineEditorState {
                return mergedEditor(makeInlineEditorContent(inlineEditorState), list: makeSnippetContent())
            }
            return makeSnippetContent()
        case .passwordVault:
            switch passwordVaultPage {
            case .remoteCredentials:
                return makePasswordVaultRemoteCredentialsContent()
            case .conflictSummary:
                return makePasswordVaultConflictSummaryContent()
            case .localCopyRecovery:
                return makePasswordVaultLocalCopyRecoveryContent()
            case .vault:
                ()
            }
            if let passwordVaultFolderEditorState {
                switch passwordVaultFolderEditorState {
                case .create:
                    return mergedEditorAtEnd(
                        makePasswordVaultFolderEditorContent(passwordVaultFolderEditorState),
                        list: makePasswordVaultContent()
                    )
                case .rename:
                    return makePasswordVaultContent()
                }
            }
            return makePasswordVaultContent()
        }
    }

    private func mergedEditor(_ editor: EmbeddedContent, list: EmbeddedContent) -> EmbeddedContent {
        EmbeddedContent(
            headerTitle: list.headerTitle, headerSubtitle: list.headerSubtitle, showsBackButton: false,
            canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil,
            rows: editor.rows + list.rows
        )
    }

    private func mergedEditorAtEnd(_ editor: EmbeddedContent, list: EmbeddedContent) -> EmbeddedContent {
        EmbeddedContent(
            headerTitle: list.headerTitle, headerSubtitle: list.headerSubtitle, showsBackButton: false,
            canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil,
            rows: list.rows + editor.rows
        )
    }

    private func makeInlineEditorContent(_ state: InlineEditorState) -> EmbeddedContent {
        if case let .newSnippetFolder(draftTitle, _) = state {
            let editor = PasswordVaultFolderEditorView(
                name: draftTitle,
                onSave: { [weak self] title in
                    self?.inlineEditorState = .newSnippetFolder(draftTitle: title, error: nil)
                    _ = self?.commitInlineEditorFromCurrentDraft()
                },
                onCancel: { [weak self] in self?.discardInlineEditor() }
            )
            inlineEditorView = nil
            return EmbeddedContent(
                headerTitle: String(localized: "Snippet"), headerSubtitle: nil, showsBackButton: false,
                canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil,
                rows: [EmbeddedRow(title: String(localized: "Folder"), view: editor, confirm: {})]
            )
        }
        let configuration: MainMenuInlineEditorView.Configuration
        let headerTitle: String
        switch state {
        case let .history(_, _, draftText, error):
            headerTitle = String(localized: "Edit History")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: nil,
                titlePlaceholder: nil,
                contentValue: draftText,
                errorMessage: error
            )
        case let .snippetFolder(_, _, draftTitle, error):
            headerTitle = String(localized: "Edit Folder")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: draftTitle,
                titlePlaceholder: String(localized: "Folder Name"),
                contentValue: nil,
                errorMessage: error
            )
        case .newSnippetFolder:
            preconditionFailure("New snippet folders use the compact row editor")
        case let .newSnippet(_, draftTitle, draftContent, error):
            headerTitle = String(localized: "New Snippet")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: draftTitle, titlePlaceholder: String(localized: "Snippet Title"),
                contentValue: draftContent, errorMessage: error
            )
        case let .snippet(_, _, _, draftTitle, draftContent, error):
            headerTitle = String(localized: "Edit Snippet")
            configuration = MainMenuInlineEditorView.Configuration(
                titleValue: draftTitle,
                titlePlaceholder: String(localized: "Snippet Title"),
                contentValue: draftContent,
                errorMessage: error
            )
        }
        let editorView = MainMenuInlineEditorView(
            configuration: configuration,
            onCommit: { [weak self] in
                _ = self?.commitInlineEditorFromCurrentDraft()
            },
            onDiscard: { [weak self] in
                self?.discardInlineEditor()
            }
        )
        inlineEditorView = editorView
        return EmbeddedContent(
            headerTitle: headerTitle,
            headerSubtitle: nil,
            showsBackButton: false,
            canGoToPreviousPage: false,
            canGoToNextPage: false,
            typeFilter: nil,
            rows: [
                EmbeddedRow(
                    title: headerTitle,
                    view: editorView,
                    confirm: {}
                )
            ]
        )
    }

    private func makeHistoryContent() -> EmbeddedContent {
        guard let historyDataSource else {
            return EmbeddedContent(
                headerTitle: historyTitle,
                headerSubtitle: nil,
                showsBackButton: false,
                canGoToPreviousPage: false,
                canGoToNextPage: false,
                typeFilter: nil,
                rows: [emptyRow(title: String(localized: "No History"))]
            )
        }

        var page = historyDataSource.fetchPage()
        if page.details.isEmpty && page.error == nil && historyDataSource.currentState().pageIndex > 0 {
            historyDataSource.updateState { $0.resetPage() }
            page = historyDataSource.fetchPage()
        }
        let state = historyDataSource.currentState()
        let rows: [EmbeddedRow]
        if let error = page.error {
            rows = [emptyRow(title: error.historyMenuTitle)]
        } else if page.details.isEmpty {
            let title = state.hasActiveSearchOptions ? String(localized: "No Results") : String(localized: "No History")
            rows = [emptyRow(title: title)]
        } else {
            rows = page.details.enumerated().map { index, detail in
                visibleHistoryIDs.append(detail.history.id)
                let rowView = historyDataSource.makeRowView(detail, index) { [weak self] in
                    self?.confirmHistorySelection(detail.history.id)
                }
                return EmbeddedRow(
                    title: detail.history.title,
                    view: rowView,
                    confirm: { [weak self] in self?.confirmHistorySelection(detail.history.id) }
                )
            }
        }

        return EmbeddedContent(
            headerTitle: state.typeFilter.title,
            headerSubtitle: "\(state.displayPage)",
            showsBackButton: false,
            canGoToPreviousPage: state.pageIndex > 0,
            canGoToNextPage: page.hasNextPage,
            typeFilter: state.typeFilter,
            rows: rows
        )
    }

    func beginEditingHistory(_ historyID: PasteboardHistory.ID) {
        guard let text = historyDataSource?.fetchEditableText(historyID) else { return }
        editingFolderShortcutID = nil
        inlineEditorState = .history(historyID, originalText: text, draftText: text, error: nil)
        reloadContentKeepingTopLeft()
    }

    private func beginEditingSnippetFolder(_ folderID: SnippetFolder.ID) {
        guard let detail = snippetDataSource?.fetchFolderDetails().first(where: { $0.folder.id == folderID }) else {
            return
        }
        editingFolderShortcutID = nil
        inlineEditorState = .snippetFolder(
            folderID,
            originalTitle: detail.folder.title,
            draftTitle: detail.folder.title,
            error: nil
        )
        reloadContentKeepingTopLeft()
    }

    private func beginEditingSnippet(_ snippetID: Snippet.ID) {
        guard let snippet = snippetDataSource?.fetchFolderDetails()
            .flatMap(\.snippets)
            .first(where: { $0.id == snippetID }) else {
            return
        }
        editingFolderShortcutID = nil
        inlineEditorState = .snippet(
            snippetID,
            originalTitle: snippet.title,
            originalContent: snippet.content,
            draftTitle: snippet.title,
            draftContent: snippet.content,
            error: nil
        )
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingSnippetFolder() {
        inlineEditorState = .newSnippetFolder(draftTitle: "", error: nil)
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingSnippet(in requestedFolderID: SnippetFolder.ID? = nil) {
        guard isWorkspaceEditing,
              let folderID = expandedSnippetFolderID,
              requestedFolderID == nil || requestedFolderID == folderID,
              enabledSnippetFolderDetails().contains(where: { $0.folder.id == folderID }) else { return }
        inlineEditorState = .newSnippet(folderID, draftTitle: "", draftContent: "", error: nil)
        reloadContentKeepingTopLeft()
    }

    @discardableResult
    private func commitInlineEditorFromCurrentDraft() -> Bool {
        guard inlineEditorState != nil else { return true }
        let draft = currentInlineEditorDraft()
        return commitInlineEditor(title: draft.title, content: draft.content)
    }

    private func currentInlineEditorDraft() -> (title: String, content: String) {
        if let inlineEditorView {
            return (inlineEditorView.draftTitle, inlineEditorView.draftContent)
        }
        switch inlineEditorState {
        case let .history(_, _, draftText, _):
            return ("", draftText)
        case let .snippetFolder(_, _, draftTitle, _):
            return (draftTitle, "")
        case let .snippet(_, _, _, draftTitle, draftContent, _):
            return (draftTitle, draftContent)
        case let .newSnippetFolder(draftTitle, _):
            return (draftTitle, "")
        case let .newSnippet(_, draftTitle, draftContent, _):
            return (draftTitle, draftContent)
        case nil:
            return ("", "")
        }
    }

    @discardableResult
    private func commitInlineEditor(title: String, content: String) -> Bool {
        guard let inlineEditorState else { return true }
        switch inlineEditorState {
        case .newSnippetFolder:
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, let folder = snippetDataSource?.createFolder(trimmedTitle) else {
                self.inlineEditorState = .newSnippetFolder(
                    draftTitle: title, error: String(localized: "Unable to create this folder.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            expandedSnippetFolderID = folder.id
        case let .newSnippet(folderID, _, _, _):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty,
                  snippetDataSource?.createSnippet(folderID, trimmedTitle, content) != nil else {
                self.inlineEditorState = .newSnippet(
                    folderID, draftTitle: title, draftContent: content,
                    error: String(localized: "Unable to create this snippet.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            expandedSnippetFolderID = folderID
        case let .history(historyID, originalText, _, _):
            guard content != originalText else {
                self.inlineEditorState = nil
                reloadContentKeepingTopLeft()
                return true
            }
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.inlineEditorState = .history(
                    historyID,
                    originalText: originalText,
                    draftText: content,
                    error: String(localized: "History text cannot be empty.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            guard historyDataSource?.updateTextHistory(historyID, content) == true else {
                self.inlineEditorState = .history(
                    historyID,
                    originalText: originalText,
                    draftText: content,
                    error: String(localized: "Unable to edit this history item.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
        case let .snippetFolder(folderID, originalTitle, _, _):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedTitle != originalTitle else {
                self.inlineEditorState = nil
                reloadContentKeepingTopLeft()
                return true
            }
            guard !trimmedTitle.isEmpty else {
                self.inlineEditorState = .snippetFolder(
                    folderID,
                    originalTitle: originalTitle,
                    draftTitle: title,
                    error: String(localized: "Folder name cannot be empty.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            guard snippetDataSource?.updateFolderTitle(folderID, trimmedTitle) == true else {
                self.inlineEditorState = .snippetFolder(
                    folderID,
                    originalTitle: originalTitle,
                    draftTitle: title,
                    error: String(localized: "A folder with this name already exists.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
        case let .snippet(snippetID, originalTitle, originalContent, _, _, _):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedTitle != originalTitle || content != originalContent else {
                self.inlineEditorState = nil
                reloadContentKeepingTopLeft()
                return true
            }
            guard !trimmedTitle.isEmpty else {
                self.inlineEditorState = .snippet(
                    snippetID,
                    originalTitle: originalTitle,
                    originalContent: originalContent,
                    draftTitle: title,
                    draftContent: content,
                    error: String(localized: "Snippet title cannot be empty.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            if content != originalContent,
               snippetDataSource?.updateSnippetContent(snippetID, content) != true {
                self.inlineEditorState = .snippet(
                    snippetID,
                    originalTitle: originalTitle,
                    originalContent: originalContent,
                    draftTitle: title,
                    draftContent: content,
                    error: String(localized: "A snippet with this content already exists in this folder.")
                )
                reloadContentKeepingTopLeft()
                return false
            }
            if trimmedTitle != originalTitle {
                snippetDataSource?.updateSnippetTitle(snippetID, trimmedTitle)
            }
        }

        self.inlineEditorState = nil
        reloadContentKeepingTopLeft()
        return true
    }

    private func discardInlineEditor() {
        inlineEditorState = nil
        reloadContentKeepingTopLeft()
    }

    private func beginEditingFolderShortcut(_ folderID: SnippetFolder.ID) {
        guard snippetDataSource?.fetchFolderDetails().contains(where: { $0.folder.id == folderID }) == true else {
            return
        }
        inlineEditorState = nil
        editingFolderShortcutID = folderID
        expandedSnippetFolderID = folderID
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(folderID)
    }

    private func recordFolderShortcut(_ keyCombo: KeyCombo) {
        guard let editingFolderShortcutID else { return }
        snippetDataSource?.updateFolderKeyCombo(editingFolderShortcutID, keyCombo)
        self.editingFolderShortcutID = nil
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(editingFolderShortcutID)
    }

    private func clearFolderShortcut(_ folderID: SnippetFolder.ID) {
        snippetDataSource?.clearFolderKeyCombo(folderID)
        if editingFolderShortcutID == folderID {
            editingFolderShortcutID = nil
        }
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(folderID)
    }

    private func clearEditingFolderShortcut() {
        guard let editingFolderShortcutID else { return }
        clearFolderShortcut(editingFolderShortcutID)
    }

    private func discardFolderShortcutEditor() {
        let folderID = editingFolderShortcutID
        editingFolderShortcutID = nil
        reloadContentKeepingTopLeft()
        if let folderID {
            selectSnippetFolderRowIfVisible(folderID)
        }
    }

    private func makeSnippetContent() -> EmbeddedContent {
        let details = enabledSnippetFolderDetails()
        visibleSnippetFolderIDs = details.map(\.folder.id)
        guard !details.isEmpty else {
            expandedSnippetFolderID = nil
            currentSnippetFolderTitle = nil
            return EmbeddedContent(
                headerTitle: snippetTitle,
                headerSubtitle: nil,
                showsBackButton: false,
                canGoToPreviousPage: false,
                canGoToNextPage: false,
                typeFilter: nil,
                rows: isWorkspaceEditing ? [newSnippetFolderCreateRow()] : [emptyRow(title: String(localized: "No Snippets"))]
            )
        }

        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let expandedID = expandedSnippetFolderID, !details.contains(where: { $0.folder.id == expandedID }) {
            expandedSnippetFolderID = query.isEmpty ? nil : details.first?.folder.id
        } else if expandedSnippetFolderID == nil && !query.isEmpty {
            expandedSnippetFolderID = details.first?.folder.id
        }
        let rows = details.enumerated().flatMap { folderIndex, detail -> [EmbeddedRow] in
            let isExpanded = detail.folder.id == expandedSnippetFolderID
            let folderTitleMatches = !query.isEmpty && detail.folder.title.localizedCaseInsensitiveContains(query)
            let folderKeyCombo = snippetDataSource?.folderKeyCombo(detail.folder.id)
            let folderShortcutText = PasteraShortcutFormatter.string(for: folderKeyCombo)
            let folderRow = EmbeddedRow(
                title: detail.folder.title,
                view: MainMenuPanelRowView(
                    title: detail.folder.title,
                    image: folderRowImage(),
                    shortcutText: folderShortcutText,
                    itemNumberText: numericShortcutText(forRowIndex: folderIndex),
                    rowKind: .snippetFolder,
                    rowHeight: MainMenuPanelLayout.snippetFolderRowHeight,
                    showsChevron: true,
                    isExpanded: isExpanded,
                    shortcutPlacement: .trailingCommand,
                    onEdit: { [weak self] in
                        self?.beginEditingSnippetFolder(detail.folder.id)
                    },
                    showsEditButton: false,
                    onEditShortcut: { [weak self] in
                        self?.beginEditingFolderShortcut(detail.folder.id)
                    },
                    onClearShortcut: folderKeyCombo == nil ? nil : { [weak self] in
                        self?.clearFolderShortcut(detail.folder.id)
                    },
                    onDelete: { [weak self] in
                        self?.confirmDeleteSnippetFolder(detail.folder.id)
                    },
                    onDoubleClick: isWorkspaceEditing
                        ? { [weak self] in self?.beginEditingSnippetFolder(detail.folder.id) } : nil,
                    dragIdentifier: isWorkspaceEditing ? "snippet-folder:\(detail.folder.id.rawValue.uuidString)" : nil,
                    onDragHover: isWorkspaceEditing && !isExpanded ? { [weak self] in
                        self?.expandSnippetFolder(detail.folder.id)
                    } : nil,
                    onDrop: isWorkspaceEditing ? { [weak self] payload, after in
                        self?.handleSnippetDrop(payload, onFolder: detail.folder.id, after: after) ?? false
                    } : nil,
                    deleteTitle: String(localized: "Delete Folder"),
                    onConfirm: { [weak self] _ in
                        self?.toggleSnippetFolder(detail.folder.id)
                    }
                ),
                confirm: { [weak self] in self?.toggleSnippetFolder(detail.folder.id) },
                role: .snippetFolder(detail.folder.id)
            )
            let folderRows: [EmbeddedRow]
            if let inlineEditorState,
               case let .snippetFolder(folderID, _, _, _) = inlineEditorState,
               folderID == detail.folder.id {
                folderRows = makeInlineEditorContent(inlineEditorState).rows
            } else {
                folderRows = [folderRow]
            }
            guard isExpanded else { return folderRows }

            currentSnippetFolderTitle = detail.folder.title
            let snippets = enabledSnippets(in: detail, folderTitleMatches: folderTitleMatches)
            visibleSnippetIDs = snippets.map(\.id)
            let shortcutEditorRows: [EmbeddedRow]
            if editingFolderShortcutID == detail.folder.id {
                shortcutEditorRows = [
                    EmbeddedRow(
                        title: "\(detail.folder.title) Shortcut",
                        view: makeFolderShortcutEditorView(for: detail.folder.id, keyCombo: folderKeyCombo),
                        confirm: {},
                        role: .none
                    )
                ]
            } else {
                shortcutEditorRows = []
            }
            let snippetRows = snippets.enumerated().flatMap { index, snippet -> [EmbeddedRow] in
                if let inlineEditorState,
                   case let .snippet(snippetID, _, _, _, _, _) = inlineEditorState,
                   snippetID == snippet.id {
                    return makeInlineEditorContent(inlineEditorState).rows
                }
                return [EmbeddedRow(
                    title: snippet.title,
                    view: MainMenuPanelRowView(
                        title: snippet.title,
                        image: nil,
                        itemNumberText: numericShortcutText(forRowIndex: index),
                        rowKind: .action,
                        indentationLevel: 1,
                        onEdit: { [weak self] in
                            self?.beginEditingSnippet(snippet.id)
                        },
                        showsEditButton: false,
                        onDelete: { [weak self] in
                            self?.confirmDeleteSnippet(snippet.id)
                        },
                        onDoubleClick: isWorkspaceEditing
                            ? { [weak self] in self?.beginEditingSnippet(snippet.id) } : nil,
                        dragIdentifier: isWorkspaceEditing ? "snippet:\(snippet.id.rawValue.uuidString)" : nil,
                        onDrop: isWorkspaceEditing ? { [weak self] payload, after in
                            self?.handleSnippetDrop(payload, onSnippet: snippet.id, after: after) ?? false
                        } : nil,
                        deleteTitle: String(localized: "Delete Snippet"),
                        onConfirm: { [weak self] _ in
                            self?.confirmSnippetSelection(snippet.id)
                        }
                    ),
                    confirm: { [weak self] in self?.confirmSnippetSelection(snippet.id) },
                    role: .snippet(snippet.id)
                )]
            }
            let createRows = isWorkspaceEditing && query.isEmpty && inlineEditorState == nil
                ? [newSnippetCreateRow(folderID: detail.folder.id)] : []
            return folderRows + shortcutEditorRows + snippetRows + createRows
        }

        if currentSnippetFolderTitle == nil,
           let expandedSnippetFolderID,
           let detail = details.first(where: { $0.folder.id == expandedSnippetFolderID }) {
            currentSnippetFolderTitle = detail.folder.title
        }

        return EmbeddedContent(
            headerTitle: snippetTitle,
            headerSubtitle: nil,
            showsBackButton: false,
            canGoToPreviousPage: false,
            canGoToNextPage: false,
            typeFilter: nil,
            rows: rows + (isWorkspaceEditing && query.isEmpty && inlineEditorState == nil
                && expandedSnippetFolderID == nil ? [newSnippetFolderCreateRow()] : [])
        )
    }

    private func newSnippetCreateRow(folderID: SnippetFolder.ID) -> EmbeddedRow {
        let view = MainMenuCreateActionsView(
            title: String(localized: "New Snippet"),
            identifier: "mainMenuContentCreateSnippetButton",
            indentationLevel: 1,
            onAction: { [weak self] in self?.beginCreatingSnippet(in: folderID) }
        )
        return EmbeddedRow(title: String(localized: "Create"), view: view, confirm: {}, participatesInNavigation: false)
    }

    private func newSnippetFolderCreateRow() -> EmbeddedRow {
        let view = MainMenuCreateActionsView(
            title: String(localized: "New Folder"),
            identifier: "mainMenuContentCreateSnippetFolderButton",
            indentationLevel: 0,
            onAction: { [weak self] in self?.beginCreatingSnippetFolder() }
        )
        return EmbeddedRow(title: String(localized: "Create"), view: view, confirm: {}, participatesInNavigation: false)
    }

    private func folderRowImage() -> NSImage? {
        NSImage(systemSymbolName: "folder", accessibilityDescription: String(localized: "Folder"))
    }

    private func makePasswordVaultContent() -> EmbeddedContent {
        guard let passwordVaultDataSource else {
            return passwordVaultFailureContent(message: String(localized: "Password Vault Unavailable"))
        }
        switch passwordVaultDataSource.state() {
        case .notConfigured:
            return passwordVaultAccessContent(
                mode: .create,
                isBusy: passwordVaultAccessModeInFlight == .create
            )
        case .preparingLocalCopy:
            passwordVaultPage = .localCopyRecovery
            return makePasswordVaultLocalCopyRecoveryContent()
        case .localCopyUnavailable:
            if passwordVaultAllowsLocalReplacement {
                return passwordVaultAccessContent(mode: .create, isBusy: false)
            }
            passwordVaultPage = .localCopyRecovery
            return makePasswordVaultLocalCopyRecoveryContent()
        case .locked:
            return passwordVaultAccessContent(
                mode: .unlock,
                isBusy: passwordVaultAccessModeInFlight == .unlock
            )
        case .unlocking:
            return passwordVaultAccessContent(mode: passwordVaultAccessModeInFlight ?? .unlock, isBusy: true)
        case .unlocked, .readOnlyWarning:
            passwordVaultAccessView = nil
            passwordVaultAccessError = nil
            break
        case let .recoveryRequired(message):
            return passwordVaultFailureContent(message: message.isEmpty
                ? String(localized: "Password Vault Unavailable") : message)
        case let .failed(message):
            return passwordVaultFailureContent(
                message: passwordVaultAccessError ?? passwordVaultFailureMessage(message)
            )
        }
        let folders: [PasswordVaultFolder]
        let entries: [PasswordVaultEntry]
        do {
            folders = try passwordVaultDataSource.fetchFolders()
            entries = try passwordVaultDataSource.fetchEntries()
        } catch PasswordVaultError.databaseNotConfigured {
            return passwordVaultAccessContent(mode: .create, isBusy: false)
        } catch PasswordVaultError.vaultLocked {
            return passwordVaultAccessContent(mode: .unlock, isBusy: false)
        } catch {
            return EmbeddedContent(
                headerTitle: String(localized: "Password Vault"),
                headerSubtitle: nil,
                showsBackButton: false,
                canGoToPreviousPage: false,
                canGoToNextPage: false,
                typeFilter: nil,
                rows: [emptyRow(title: String(localized: "Password Vault Unavailable"))]
            )
        }
        if let expandedID = expandedPasswordVaultFolderID, !folders.contains(where: { $0.id == expandedID }) {
            expandedPasswordVaultFolderID = nil
        }
        let query = passwordVaultSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingEntries = entries.filter { query.isEmpty || $0.matches(query) }
        let allowsNumberShortcuts = passwordVaultEditorState == nil && passwordVaultFolderEditorState == nil
        let rows = folders.flatMap { folder -> [EmbeddedRow] in
            let folderEntries = matchingEntries.filter { $0.folderID == folder.id }
            guard query.isEmpty || !folderEntries.isEmpty || folder.name.localizedCaseInsensitiveContains(query) else { return [] }
            let isExpanded = query.isEmpty ? folder.id == expandedPasswordVaultFolderID : true
            let folderNumber = allowsNumberShortcuts && query.isEmpty && expandedPasswordVaultFolderID == nil
                ? numericShortcutText(forRowIndex: visiblePasswordVaultFolderIDs.count) : nil
            visiblePasswordVaultFolderIDs.append(folder.id)
            let folderRow = EmbeddedRow(
                title: folder.name,
                view: MainMenuPanelRowView(
                    title: folder.name,
                    image: folderRowImage(),
                    itemNumberText: folderNumber,
                    rowKind: .snippetFolder,
                    showsChevron: true,
                    isExpanded: isExpanded,
                    onEdit: { [weak self] in self?.passwordVaultFolderEditorState = .rename(folder, draftName: folder.name, error: nil); self?.reloadContentKeepingTopLeft() },
                    showsEditButton: false,
                    onDelete: { [weak self] in self?.deletePasswordVaultFolder(folder.id) },
                    onDoubleClick: isWorkspaceEditing ? { [weak self] in
                            self?.passwordVaultFolderEditorState = .rename(folder, draftName: folder.name, error: nil)
                            self?.reloadContentKeepingTopLeft()
                        } : nil,
                    dragIdentifier: isWorkspaceEditing ? "password-folder:\(folder.id.uuidString)" : nil,
                    onDragHover: isWorkspaceEditing && !isExpanded ? { [weak self] in
                        self?.expandedPasswordVaultFolderID = folder.id
                        self?.reloadContentKeepingTopLeft()
                    } : nil,
                    onDrop: isWorkspaceEditing ? { [weak self] payload, after in
                        self?.handlePasswordDrop(payload, onFolder: folder.id, after: after) ?? false
                    } : nil,
                    deleteTitle: String(localized: "Delete Folder"),
                    onConfirm: { [weak self] _ in self?.togglePasswordVaultFolder(folder.id) }
                ),
                confirm: { [weak self] in self?.togglePasswordVaultFolder(folder.id) }
            )
            let folderRows: [EmbeddedRow]
            if let passwordVaultFolderEditorState,
               case let .rename(editingFolder, _, _) = passwordVaultFolderEditorState,
               editingFolder.id == folder.id {
                folderRows = makePasswordVaultFolderEditorContent(passwordVaultFolderEditorState).rows
            } else {
                folderRows = [folderRow]
            }
            guard isExpanded else { return folderRows }
            let entryRows = folderEntries.flatMap { entry -> [EmbeddedRow] in
                let numberShortcut = allowsNumberShortcuts
                    ? numericShortcutText(forRowIndex: visiblePasswordVaultEntryIDs.count) : nil
                let usernameShortcut = numberShortcut.map { "⌃\($0)" }
                visiblePasswordVaultEntryIDs.append(entry.id)
                let row = EmbeddedRow(
                    title: entry.title,
                    view: MainMenuPanelRowView(
                        title: entry.title,
                        image: MainMenuModeIcons.passwordVault(),
                        itemNumberText: numberShortcut,
                        rowKind: .action,
                        indentationLevel: 1,
                        contextActions: [
                            .init(title: String(localized: "Paste Username"), keyEquivalent: numberShortcut ?? "", modifierFlags: .control, action: { [weak self] in
                                self?.pastePasswordVaultUsername(entry.id)
                            }),
                            .init(title: String(localized: "Paste Password"), keyEquivalent: numberShortcut ?? "", modifierFlags: [], action: { [weak self] in
                                self?.pastePasswordVaultPassword(entry.id)
                            })
                        ],
                        quickActions: isWorkspaceEditing ? [] : [
                            .init(
                                identifier: "mainMenuPasswordPasteUsernameButton",
                                symbolName: "person.text.rectangle",
                                title: String(localized: "Paste Username"),
                                shortcutText: usernameShortcut,
                                action: { [weak self] in self?.pastePasswordVaultUsername(entry.id) }
                            ),
                            .init(
                                identifier: "mainMenuPasswordPastePasswordButton",
                                symbolName: "key.fill",
                                title: String(localized: "Paste Password"),
                                shortcutText: numberShortcut,
                                action: { [weak self] in self?.pastePasswordVaultPassword(entry.id) }
                            ),
                            .init(
                                identifier: "mainMenuPasswordMoreButton",
                                symbolName: "ellipsis",
                                title: String(localized: "More"),
                                shortcutText: nil,
                                action: nil
                            )
                        ],
                        onEdit: { [weak self] in self?.beginEditingPasswordVaultEntry(entry.id) },
                        showsEditButton: false,
                        onDelete: { [weak self] in self?.deletePasswordVaultEntry(entry.id) },
                        showsDeleteButton: isWorkspaceEditing,
                        onDoubleClick: isWorkspaceEditing
                            ? { [weak self] in self?.beginEditingPasswordVaultEntry(entry.id) } : nil,
                        dragIdentifier: isWorkspaceEditing ? "password-entry:\(entry.id.uuidString)" : nil,
                        onDrop: isWorkspaceEditing ? { [weak self] payload, after in
                            self?.handlePasswordDrop(payload, onEntry: entry.id, after: after) ?? false
                        } : nil,
                        deleteTitle: String(localized: "Delete Password"),
                        onConfirm: { [weak self] _ in self?.copyPasswordVaultEntry(entry.id) }
                    ),
                    confirm: { [weak self] in self?.copyPasswordVaultEntry(entry.id) },
                    role: .passwordEntry(entry.id)
                )
                row.view.toolTip = [entry.title,
                    numberShortcut.map { "\(String(localized: "Paste Password"))  \($0)" },
                    usernameShortcut.map { "\(String(localized: "Paste Username"))  \($0)" }
                ].compactMap { $0 }.joined(separator: "  ·  ")
                row.view.setAccessibilityHelp(row.view.toolTip)
                guard passwordVaultEditingEntryID == entry.id else { return [row] }
                return [passwordVaultStepEditorRow()]
            }
            let createEditorRows = passwordVaultCreatingFolderID == folder.id
                ? [passwordVaultStepEditorRow()] : []
            let createRows = isWorkspaceEditing && query.isEmpty
                && passwordVaultEditorState == nil && passwordVaultFolderEditorState == nil
                ? [newPasswordVaultCreateRow(folderID: folder.id)] : []
            return folderRows + entryRows + createEditorRows + createRows
        }
        let trailingCreateRows = isWorkspaceEditing && query.isEmpty
            && passwordVaultEditorState == nil && passwordVaultFolderEditorState == nil
            && expandedPasswordVaultFolderID == nil ? [newPasswordVaultFolderCreateRow()] : []
        let contentRows = rows + trailingCreateRows
        let visibleRows = passwordVaultStatusMessage.map { [emptyRow(title: $0)] + contentRows }
            ?? contentRows
        return EmbeddedContent(
            headerTitle: String(localized: "Password Vault"),
            headerSubtitle: nil,
            showsBackButton: false,
            canGoToPreviousPage: false,
            canGoToNextPage: false,
            typeFilter: nil,
            rows: visibleRows.isEmpty && !query.isEmpty
                ? [emptyRow(title: String(localized: "No Results"))]
                : visibleRows
        )
    }

    private func passwordVaultAccessContent(
        mode: PasswordVaultAccessView.Mode,
        isBusy: Bool
    ) -> EmbeddedContent {
        let view = PasswordVaultAccessView(
            mode: mode,
            storageMode: passwordVaultCreateStorageMode,
            canQuickUnlock: mode == .unlock && passwordVaultQuickUnlockAvailability == .available,
            isBusy: isBusy,
            errorMessage: passwordVaultAccessError,
            onStorageModeChange: { [weak self] storageMode in
                self?.passwordVaultCreateStorageMode = storageMode
            },
            onSubmit: { [weak self] password, storageMode in
                self?.passwordVaultCreateStorageMode = storageMode
                self?.submitPasswordVaultAccess(password: password, mode: mode)
            },
            onQuickUnlock: { [weak self] in self?.performPasswordVaultQuickUnlock() }
        )
        passwordVaultAccessView = view
        let title = mode == .create
            ? String(localized: "Set Master Password") : String(localized: "Unlock Vault")
        return EmbeddedContent(
            headerTitle: String(localized: "Password Vault"), headerSubtitle: nil,
            showsBackButton: false, canGoToPreviousPage: false, canGoToNextPage: false,
            typeFilter: nil,
            rows: [EmbeddedRow(title: title, view: view, confirm: { [weak view] in view?.submit() }, participatesInNavigation: false)]
        )
    }

    // The recovery page intentionally keeps all branch choices in one native view.
    // swiftlint:disable:next function_body_length
    private func makePasswordVaultLocalCopyRecoveryContent() -> EmbeddedContent {
        guard let passwordVaultDataSource else {
            return passwordVaultFailureContent(message: String(localized: "Password Vault Unavailable"))
        }
        let state = passwordVaultDataSource.state()
        let isPreparing: Bool
        switch state {
        case .preparingLocalCopy:
            isPreparing = true
        case .localCopyUnavailable:
            isPreparing = false
        default:
            passwordVaultPage = .vault
            passwordVaultLocalRecoveryShowsWarning = false
            return makePasswordVaultContent()
        }

        let view: PasswordVaultInlineActionView
        if passwordVaultLocalRecoveryShowsWarning {
            view = PasswordVaultInlineActionView(
                symbolName: "arrow.triangle.branch",
                symbolColor: .systemOrange,
                title: String(localized: "Create a Separate Local Vault?"),
                messages: [
                    String(localized: "Creating a new local vault starts a separate data branch."),
                    String(localized: "The previous OneDrive vault will not be overwritten. You can reconnect it later and decide how to merge the two copies.")
                ],
                actions: [
                    .init(
                        title: String(localized: "Create New Local Vault"),
                        identifier: "passwordVaultRecoveryConfirmReplacement",
                        style: .danger,
                        handler: { [weak self] in
                            self?.passwordVaultAllowsLocalReplacement = true
                            self?.passwordVaultLocalRecoveryShowsWarning = false
                            self?.passwordVaultPage = .vault
                            self?.reloadContentKeepingTopLeft()
                        }
                    ),
                    .init(
                        title: String(localized: "Back"),
                        identifier: "passwordVaultRecoveryWarningBack",
                        style: .secondary,
                        handler: { [weak self] in
                            self?.passwordVaultLocalRecoveryShowsWarning = false
                            self?.reloadContentKeepingTopLeft()
                        }
                    )
                ]
            )
        } else {
            var actions = [PasswordVaultInlineActionView.Action]()
            let oneDriveStatus = oneDriveStatusService.currentStatus()
            if case .notRunning = oneDriveStatus {
                actions.append(.init(
                    title: String(localized: "Start OneDrive"),
                    identifier: "passwordVaultRecoveryStartOneDrive",
                    style: .primary,
                    handler: { [weak self] in
                        guard let self else { return }
                        if self.passwordVaultSyncDataSource?.startOneDrive() != true {
                            self.passwordVaultInlineActionView?.setError(
                                String(localized: "OneDrive could not be started.")
                            )
                        }
                    }
                ))
            }
            actions.append(.init(
                title: isPreparing ? String(localized: "Preparing…") : String(localized: "Try Again"),
                identifier: "passwordVaultRecoveryRetry",
                style: actions.isEmpty ? .primary : .secondary,
                handler: { [weak self] in
                    self?.passwordVaultDataSource?.retryLocalPreparation()
                }
            ))
            actions.append(.init(
                title: String(localized: "Continue with a New Local Vault"),
                identifier: "passwordVaultRecoveryContinueLocal",
                style: .secondary,
                handler: { [weak self] in
                    self?.passwordVaultLocalRecoveryShowsWarning = true
                    self?.reloadContentKeepingTopLeft()
                }
            ))
            view = PasswordVaultInlineActionView(
                symbolName: isPreparing ? "arrow.triangle.2.circlepath" : "exclamationmark.icloud.fill",
                symbolColor: isPreparing ? .controlAccentColor : .systemRed,
                title: isPreparing
                    ? String(localized: "Preparing the Local Vault")
                    : String(localized: "The local password vault could not be prepared."),
                messages: [isPreparing
                    ? String(localized: "Pastera is creating a local working copy. No password is needed yet.")
                    : oneDriveStatus.isRunning
                        ? String(localized: "OneDrive is running, but the cloud vault has not finished downloading. Wait for OneDrive to finish syncing, then try again. Your cloud copy remains unchanged.")
                        : String(localized: "If OneDrive was disconnected, start it and retry. Your cloud copy remains unchanged.")],
                actions: actions
            )
        }
        passwordVaultInlineActionView = view
        return passwordVaultActionContent(
            headerTitle: String(localized: "Local Vault Recovery"),
            rowTitle: isPreparing
                ? String(localized: "Preparing local vault")
                : String(localized: "Local vault is not ready"),
            view: view,
            showsBackButton: passwordVaultLocalRecoveryShowsWarning
        )
    }

    private func makePasswordVaultRemoteCredentialsContent() -> EmbeddedContent {
        guard let passwordVaultSyncDataSource else {
            return passwordVaultFailureContent(message: String(localized: "OneDrive sync is unavailable"))
        }
        let view = PasswordVaultRemoteCredentialsView { [weak self] password in
            passwordVaultSyncDataSource.retryWithRemotePassword(password) { result in
                self?.finishRemoteCredentialRetry(result)
            }
        }
        passwordVaultRemoteCredentialsView = view
        return passwordVaultActionContent(
            headerTitle: String(localized: "OneDrive Password"),
            rowTitle: String(localized: "Unlock the OneDrive Copy"),
            view: view,
            showsBackButton: true
        )
    }

    private func finishRemoteCredentialRetry(_ result: Result<Void, PasswordVaultSyncFailure>) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.finishRemoteCredentialRetry(result) }
            return
        }
        switch result {
        case .success:
            let snapshot = passwordVaultSyncDataSource?.snapshot()
            passwordVaultPage = (snapshot?.conflictCopyCount ?? 0) > 0 ? .conflictSummary : .vault
            passwordVaultRemoteCredentialsView = nil
            reloadContentKeepingTopLeft()
        case .failure(.remoteCredentialsRequired):
            passwordVaultRemoteCredentialsView?.setError(
                String(localized: "The OneDrive vault master password is incorrect.")
            )
        case .failure(let failure):
            passwordVaultRemoteCredentialsView?.setError(passwordVaultSyncFailureMessage(failure))
        }
    }

    private func makePasswordVaultConflictSummaryContent() -> EmbeddedContent {
        let snapshot = passwordVaultSyncDataSource?.snapshot() ?? PasswordVaultSyncSnapshot(
            mode: .localOnly,
            phase: .disabled,
            localVaultAvailable: true,
            remoteVaultAvailable: nil,
            pendingChangeCount: 0,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
        let view = PasswordVaultInlineActionView(
            symbolName: snapshot.conflictCopyCount > 0 ? "checkmark.trianglebadge.exclamationmark" : "checkmark.circle.fill",
            symbolColor: snapshot.conflictCopyCount > 0 ? .systemYellow : .systemGreen,
            title: String(localized: "Sync Merge Complete"),
            messages: [
                String(localized: "Pastera automatically combined compatible local and OneDrive changes."),
                String(format: String(localized: "%lld conflict copies were kept for review."), Int64(snapshot.conflictCopyCount)),
                String(format: String(localized: "%lld local changes are still waiting."), Int64(snapshot.pendingChangeCount))
            ],
            actions: [
                .init(
                    title: String(localized: "View Conflict Copies"),
                    identifier: "passwordVaultConflictViewCopies",
                    style: .primary,
                    handler: { [weak self] in self?.showPasswordVaultConflictCopies() }
                ),
                .init(
                    title: String(localized: "Return to Vault"),
                    identifier: "passwordVaultConflictReturnToVault",
                    style: .secondary,
                    handler: { [weak self] in
                        self?.passwordVaultPage = .vault
                        self?.reloadContentKeepingTopLeft()
                    }
                )
            ]
        )
        passwordVaultInlineActionView = view
        return passwordVaultActionContent(
            headerTitle: String(localized: "Sync Result"),
            rowTitle: String(localized: "Sync Merge Complete"),
            view: view,
            showsBackButton: true
        )
    }

    private func showPasswordVaultConflictCopies() {
        passwordVaultSearchQuery = "(Conflict)"
        searchField.stringValue = passwordVaultSearchQuery
        isSearchVisible = true
        passwordVaultPage = .vault
        reloadContentKeepingTopLeft()
    }

    private func passwordVaultActionContent(
        headerTitle: String,
        rowTitle: String,
        view: NSView,
        showsBackButton: Bool
    ) -> EmbeddedContent {
        EmbeddedContent(
            headerTitle: headerTitle,
            headerSubtitle: nil,
            showsBackButton: showsBackButton,
            canGoToPreviousPage: false,
            canGoToNextPage: false,
            typeFilter: nil,
            rows: [EmbeddedRow(title: rowTitle, view: view, confirm: {}, participatesInNavigation: false)]
        )
    }

    private func passwordVaultFailureContent(message: String) -> EmbeddedContent {
        passwordVaultAccessView = nil
        passwordVaultAccessError = nil
        return EmbeddedContent(
            headerTitle: String(localized: "Password Vault"), headerSubtitle: nil,
            showsBackButton: false, canGoToPreviousPage: false, canGoToNextPage: false,
            typeFilter: nil, rows: [emptyRow(title: message)]
        )
    }

    private func submitPasswordVaultAccess(password: String, mode: PasswordVaultAccessView.Mode) {
        passwordVaultAccessError = nil
        passwordVaultAccessModeInFlight = mode
        let completion: (Result<Void, PasswordVaultError>) -> Void = { [weak self] result in
            self?.handlePasswordVaultAccessResult(result, mode: mode)
        }
        switch mode {
        case .create:
            passwordVaultDataSource?.createDatabase(password, completion)
        case .unlock:
            passwordVaultDataSource?.unlock(password, completion)
        }
        reloadContentKeepingTopLeft()
    }

    private func attemptAutomaticPasswordVaultQuickUnlockIfNeeded() {
        guard !passwordVaultAutomaticQuickUnlockAttempted,
              passwordVaultDataSource?.state() == .locked else { return }
        passwordVaultAutomaticQuickUnlockAttempted = true
        passwordVaultQuickUnlockAvailability = .checking
        passwordVaultDataSource?.checkQuickUnlockAvailability { [weak self] isAvailable in
            guard let self else { return }
            self.passwordVaultQuickUnlockAvailability = isAvailable ? .available : .unavailable
            guard isAvailable, self.passwordVaultDataSource?.state() == .locked else { return }
            self.performPasswordVaultQuickUnlock()
        }
    }

    private func performPasswordVaultQuickUnlock() {
        passwordVaultAccessError = nil
        passwordVaultAccessModeInFlight = .unlock
        passwordVaultDataSource?.unlockWithQuickKey { [weak self] result in
            self?.handlePasswordVaultAccessResult(result, mode: .unlock)
        }
        reloadContentKeepingTopLeft()
    }

    private func handlePasswordVaultAccessResult(
        _ result: Result<Void, PasswordVaultError>,
        mode: PasswordVaultAccessView.Mode
    ) {
        passwordVaultAccessView?.clearSecrets()
        passwordVaultAccessModeInFlight = nil
        switch result {
        case .success:
            passwordVaultAccessError = nil
            passwordVaultAllowsLocalReplacement = false
            if mode == .create, passwordVaultCreateStorageMode == .oneDrive {
                enableConfiguredOneDriveAfterCreation()
                return
            }
        case .failure(.userCancelled):
            passwordVaultAccessError = nil
        case let .failure(error):
            passwordVaultAccessError = passwordVaultMessage(error)
        }
        reloadContentKeepingTopLeft()
    }

    private func enableConfiguredOneDriveAfterCreation() {
        guard let passwordVaultSyncDataSource else {
            passwordVaultStatusMessage = passwordVaultSyncFailureMessage(.folderUnavailable)
            passwordVaultPage = .vault
            reloadContentKeepingTopLeft()
            return
        }
        passwordVaultSyncDataSource.enableConfiguredOneDrive(nil) { [weak self] result in
            self?.finishConfiguredOneDriveEnable(result)
        }
    }

    private func finishConfiguredOneDriveEnable(_ result: Result<Void, PasswordVaultSyncFailure>) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.finishConfiguredOneDriveEnable(result) }
            return
        }
        switch result {
        case .success:
            passwordVaultStatusMessage = nil
            passwordVaultPage = (passwordVaultSyncDataSource?.snapshot().conflictCopyCount ?? 0) > 0
                ? .conflictSummary
                : .vault
        case .failure(.remoteCredentialsRequired):
            passwordVaultPage = .remoteCredentials
        case .failure(let failure):
            passwordVaultStatusMessage = passwordVaultSyncFailureMessage(failure)
            passwordVaultPage = .vault
        }
        reloadContentKeepingTopLeft()
    }

    private func resetPasswordVaultAccessPresentation() {
        passwordVaultAccessView?.clearSecrets()
        passwordVaultAccessView = nil
        passwordVaultCreateStorageMode = .localOnly
        passwordVaultAccessError = nil
        passwordVaultAccessModeInFlight = nil
        passwordVaultAutomaticQuickUnlockAttempted = false
        passwordVaultQuickUnlockAvailability = .unknown
        passwordVaultRemoteCredentialsView?.clearSecret()
        passwordVaultRemoteCredentialsView = nil
        passwordVaultInlineActionView = nil
        passwordVaultLocalRecoveryShowsWarning = false
        passwordVaultAllowsLocalReplacement = false
        passwordVaultSuppressesRemotePrompt = false
    }

    private func newPasswordVaultCreateRow(folderID: PasswordVaultFolder.ID) -> EmbeddedRow {
        let view = MainMenuCreateActionsView(
            title: String(localized: "New Password"),
            identifier: "mainMenuContentCreatePasswordButton",
            indentationLevel: 1,
            onAction: { [weak self] in self?.beginCreatingPasswordVaultEntry(in: folderID) }
        )
        return EmbeddedRow(title: String(localized: "Create"), view: view, confirm: {}, participatesInNavigation: false)
    }

    private func newPasswordVaultFolderCreateRow() -> EmbeddedRow {
        let view = MainMenuCreateActionsView(
            title: String(localized: "New Folder"),
            identifier: "mainMenuContentCreatePasswordFolderButton",
            indentationLevel: 0,
            onAction: { [weak self] in self?.beginCreatingPasswordVaultFolder() }
        )
        return EmbeddedRow(title: String(localized: "Create"), view: view, confirm: {}, participatesInNavigation: false)
    }

    private var passwordVaultCreatingFolderID: PasswordVaultFolder.ID? {
        guard case let .create(draft, _, _) = passwordVaultEditorState else { return nil }
        return draft.folderID
    }

    private var passwordVaultEditingEntryID: PasswordVaultEntry.ID? {
        guard case let .edit(id, _, _, _) = passwordVaultEditorState else { return nil }
        return id
    }

    private func passwordVaultStepEditorRow() -> EmbeddedRow {
        guard let passwordVaultEditorState else {
            return emptyRow(title: String(localized: "Password Vault Unavailable"))
        }
        let draft: PasswordVaultDraft
        let step: PasswordVaultEditorStep
        switch passwordVaultEditorState {
        case let .create(value, currentStep, _), let .edit(_, value, currentStep, _):
            (draft, step) = (value, currentStep)
        }
        let value: String
        switch step {
        case .title: value = draft.title
        case .username: value = draft.username
        case .password: value = draft.password
        }
        let editor = PasswordVaultStepEditorView(
            step: step,
            value: value,
            onCommit: { [weak self] value in self?.commitPasswordVaultStep(value) },
            onEscape: { [weak self] in self?.goBackPasswordVaultStep() }
        )
        passwordVaultStepEditorView = editor
        return EmbeddedRow(title: String(localized: "Password"), view: editor, confirm: {}, participatesInNavigation: false)
    }

    private func makePasswordVaultFolderEditorContent(_ state: PasswordVaultFolderEditorState) -> EmbeddedContent {
        let name: String
        let error: String?
        switch state {
        case let .create(draftName, message): (name, error) = (draftName, message)
        case let .rename(_, draftName, message): (name, error) = (draftName, message)
        }
        let editor = PasswordVaultFolderEditorView(
            name: name,
            onSave: { [weak self] name in self?.savePasswordVaultFolder(name: name) },
            onCancel: { [weak self] in self?.passwordVaultFolderEditorState = nil; self?.reloadContentKeepingTopLeft() }
        )
        passwordVaultFolderEditorView = editor
        let rows = error.map { [emptyRow(title: $0), EmbeddedRow(title: String(localized: "Folder"), view: editor, confirm: {})] }
            ?? [EmbeddedRow(title: String(localized: "Folder"), view: editor, confirm: {})]
        return EmbeddedContent(
            headerTitle: String(localized: "Folder"), headerSubtitle: nil, showsBackButton: false,
            canGoToPreviousPage: false, canGoToNextPage: false, typeFilter: nil, rows: rows
        )
    }

    private func deletePasswordVaultEntry(_ id: PasswordVaultEntry.ID) {
        guard confirmPasswordVaultDeletion(.entry(id)) else { return }
        passwordVaultDataSource?.deleteEntry(id) { [weak self] result in
            self?.handlePasswordVaultResult(result)
        }
    }

    private func togglePasswordVaultFolder(_ folderID: PasswordVaultFolder.ID) {
        expandedPasswordVaultFolderID = expandedPasswordVaultFolderID == folderID ? nil : folderID
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingPasswordVaultEntry(in requestedFolderID: PasswordVaultFolder.ID? = nil) {
        let folders = (try? passwordVaultDataSource?.fetchFolders()) ?? []
        guard isWorkspaceEditing,
              let folderID = expandedPasswordVaultFolderID,
              requestedFolderID == nil || requestedFolderID == folderID,
              folders.contains(where: { $0.id == folderID }) else { return }
        expandedPasswordVaultFolderID = folderID
        passwordVaultEditorState = .create(PasswordVaultDraft(
            folderID: folderID, title: "", website: "", username: "", note: "", password: ""
        ), step: .title, error: nil)
        reloadContentKeepingTopLeft()
    }

    private func beginEditingPasswordVaultEntry(_ id: PasswordVaultEntry.ID) {
        passwordVaultDataSource?.loadDraft(id) { [weak self] result in
            switch result {
            case let .success(draft):
                self?.expandedPasswordVaultFolderID = draft.folderID
                self?.passwordVaultEditorState = .edit(id, draft, step: .title, error: nil)
                self?.reloadContentKeepingTopLeft()
            case .failure(.userCancelled):
                break
            case let .failure(error):
                self?.passwordVaultStatusMessage = self?.passwordVaultMessage(error)
                self?.reloadContentKeepingTopLeft()
            }
        }
    }

    private func commitPasswordVaultStep(_ value: String) {
        guard let state = passwordVaultEditorState else { return }
        var draft: PasswordVaultDraft
        let step: PasswordVaultEditorStep
        let entryID: PasswordVaultEntry.ID?
        switch state {
        case let .create(value, currentStep, _):
            (draft, step, entryID) = (value, currentStep, nil)
        case let .edit(id, value, currentStep, _):
            (draft, step, entryID) = (value, currentStep, id)
        }

        switch step {
        case .title:
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                updatePasswordVaultEditorError(String(localized: "Enter a name."), draft: draft)
                return
            }
            draft.title = title
            setPasswordVaultEditorState(entryID: entryID, draft: draft, step: .username)
        case .username:
            draft.username = value.trimmingCharacters(in: .whitespacesAndNewlines)
            setPasswordVaultEditorState(entryID: entryID, draft: draft, step: .password)
        case .password:
            guard !value.isEmpty else {
                updatePasswordVaultEditorError(String(localized: "Enter a password."), draft: draft)
                return
            }
            draft.password = value
            passwordVaultStepEditorView?.value = ""
            savePasswordVaultDraft(draft)
            return
        }
        reloadContentKeepingTopLeft()
    }

    private func goBackPasswordVaultStep() {
        guard let state = passwordVaultEditorState else { return }
        let draft: PasswordVaultDraft
        let step: PasswordVaultEditorStep
        let entryID: PasswordVaultEntry.ID?
        switch state {
        case let .create(value, currentStep, _): (draft, step, entryID) = (value, currentStep, nil)
        case let .edit(id, value, currentStep, _): (draft, step, entryID) = (value, currentStep, id)
        }
        switch step {
        case .title:
            discardPasswordVaultEditor()
            return
        case .username:
            setPasswordVaultEditorState(entryID: entryID, draft: draft, step: .title)
        case .password:
            var clearedDraft = draft
            clearedDraft.password = ""
            setPasswordVaultEditorState(entryID: entryID, draft: clearedDraft, step: .username)
        }
        reloadContentKeepingTopLeft()
    }

    private func setPasswordVaultEditorState(
        entryID: PasswordVaultEntry.ID?,
        draft: PasswordVaultDraft,
        step: PasswordVaultEditorStep,
        error: String? = nil
    ) {
        if let entryID {
            passwordVaultEditorState = .edit(entryID, draft, step: step, error: error)
        } else {
            passwordVaultEditorState = .create(draft, step: step, error: error)
        }
    }

    private func preservePasswordVaultEditorDrafts() {
        if let state = passwordVaultEditorState, let editor = passwordVaultStepEditorView {
            var draft: PasswordVaultDraft
            let step: PasswordVaultEditorStep
            let entryID: PasswordVaultEntry.ID?
            let error: String?
            switch state {
            case let .create(value, currentStep, message):
                (draft, step, entryID, error) = (value, currentStep, nil, message)
            case let .edit(id, value, currentStep, message):
                (draft, step, entryID, error) = (value, currentStep, id, message)
            }
            switch step {
            case .title: draft.title = editor.value
            case .username: draft.username = editor.value
            case .password: draft.password = editor.value
            }
            setPasswordVaultEditorState(entryID: entryID, draft: draft, step: step, error: error)
        }
        if let state = passwordVaultFolderEditorState, let editor = passwordVaultFolderEditorView {
            switch state {
            case let .create(_, error):
                passwordVaultFolderEditorState = .create(draftName: editor.draftName, error: error)
            case let .rename(folder, _, error):
                passwordVaultFolderEditorState = .rename(folder, draftName: editor.draftName, error: error)
            }
        }
    }

    private func savePasswordVaultDraft(_ draft: PasswordVaultDraft) {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updatePasswordVaultEditorError(String(localized: "Enter a name."), draft: draft)
            return
        }
        guard !draft.password.isEmpty else {
            updatePasswordVaultEditorError(String(localized: "Enter a password."), draft: draft)
            return
        }
        switch passwordVaultEditorState {
        case .create:
            passwordVaultDataSource?.createEntry(draft) { [weak self] result in
                self?.finishPasswordVaultSave(result, draft: draft)
            }
        case let .edit(id, _, _, _):
            passwordVaultDataSource?.updateEntry(id, draft) { [weak self] result in
                self?.finishPasswordVaultSave(result, draft: draft)
            }
        case nil:
            break
        }
    }

    private func finishPasswordVaultSave(_ result: Result<Void, PasswordVaultError>, draft: PasswordVaultDraft) {
        switch result {
        case .success:
            passwordVaultEditorState = nil
            expandedPasswordVaultFolderID = draft.folderID
        case .failure(.userCancelled):
            return
        case let .failure(error):
            updatePasswordVaultEditorError(passwordVaultMessage(error), draft: draft)
            return
        }
        reloadContentKeepingTopLeft()
    }

    private func updatePasswordVaultEditorError(_ message: String, draft: PasswordVaultDraft) {
        switch passwordVaultEditorState {
        case let .create(_, step, _):
            passwordVaultEditorState = .create(draft, step: step, error: message)
        case let .edit(id, _, step, _):
            passwordVaultEditorState = .edit(id, draft, step: step, error: message)
        case nil:
            break
        }
        reloadContentKeepingTopLeft()
    }

    private func discardPasswordVaultEditor() {
        passwordVaultEditorState = nil
        passwordVaultStepEditorView = nil
        reloadContentKeepingTopLeft()
    }

    private func copyPasswordVaultEntry(_ id: PasswordVaultEntry.ID) {
        passwordVaultDataSource?.copyPassword(id) { [weak self] result in
            self?.handlePasswordVaultResult(result)
        }
    }

    private func pastePasswordVaultUsername(_ id: PasswordVaultEntry.ID) {
        passwordVaultDataSource?.pasteUsername(id, pasteTargetContext) { [weak self] result in
            self?.handlePasswordVaultPasteResult(result)
        }
    }

    private func pastePasswordVaultPassword(_ id: PasswordVaultEntry.ID) {
        passwordVaultDataSource?.pastePassword(id, pasteTargetContext) { [weak self] result in
            self?.handlePasswordVaultPasteResult(result)
        }
    }

    private func handlePasswordVaultPasteResult(_ result: Result<Void, PasswordVaultError>) {
        switch result {
        case .success:
            close()
        case .failure(.userCancelled):
            break
        case let .failure(error):
            passwordVaultStatusMessage = passwordVaultMessage(error)
            reloadContentKeepingTopLeft()
        }
    }

    private func handlePasswordVaultResult(_ result: Result<Void, PasswordVaultError>) {
        passwordVaultPendingDeletion = nil
        switch result {
        case .success, .failure(.userCancelled):
            passwordVaultStatusMessage = nil
        case let .failure(error):
            passwordVaultStatusMessage = passwordVaultMessage(error)
        }
        reloadContentKeepingTopLeft()
    }

    private func beginCreatingPasswordVaultFolder() {
        passwordVaultFolderEditorState = .create(draftName: "", error: nil)
        reloadContentKeepingTopLeft()
    }

    private func savePasswordVaultFolder(name: String) {
        switch passwordVaultFolderEditorState {
        case .create:
            passwordVaultDataSource?.createFolder(name) { [weak self] result in
                self?.finishPasswordVaultFolderSave(result)
            }
        case let .rename(folder, _, _):
            passwordVaultDataSource?.renameFolder(folder.id, name) { [weak self] result in
                self?.finishPasswordVaultFolderSave(result)
            }
        case nil:
            return
        }
    }

    private func finishPasswordVaultFolderSave(_ result: Result<PasswordVaultFolder, PasswordVaultError>) {
        switch result {
        case let .success(folder):
            expandedPasswordVaultFolderID = folder.id
            passwordVaultFolderEditorState = nil
        case let .failure(error):
            switch passwordVaultFolderEditorState {
            case let .create(draftName, _):
                passwordVaultFolderEditorState = .create(draftName: draftName, error: passwordVaultMessage(error))
            case let .rename(folder, draftName, _):
                passwordVaultFolderEditorState = .rename(folder, draftName: draftName, error: passwordVaultMessage(error))
            case nil:
                break
            }
        }
        reloadContentKeepingTopLeft()
    }

    private func deletePasswordVaultFolder(_ id: PasswordVaultFolder.ID) {
        guard confirmPasswordVaultDeletion(.folder(id)) else { return }
        passwordVaultDataSource?.deleteFolder(id) { [weak self] result in
            self?.passwordVaultPendingDeletion = nil
            switch result {
            case .success:
                if self?.expandedPasswordVaultFolderID == id { self?.expandedPasswordVaultFolderID = nil }
                self?.passwordVaultStatusMessage = nil
            case let .failure(error):
                self?.passwordVaultStatusMessage = self?.passwordVaultMessage(error)
            }
            self?.reloadContentKeepingTopLeft()
        }
    }

    private func confirmPasswordVaultDeletion(_ deletion: PasswordVaultPendingDeletion) -> Bool {
        guard passwordVaultPendingDeletion == deletion else {
            passwordVaultPendingDeletion = deletion
            passwordVaultStatusMessage = String(localized: "Delete again to confirm.")
            reloadContentKeepingTopLeft()
            return false
        }
        passwordVaultStatusMessage = nil
        return true
    }

    private func passwordVaultMessage(_ error: PasswordVaultError) -> String {
        switch error {
        case .invalidTitle: return String(localized: "Enter a name.")
        case .invalidUsername: return String(localized: "This password entry has no username.")
        case .invalidPassword: return String(localized: "Enter a password.")
        case .duplicateFolder: return String(localized: "A folder with this name already exists.")
        case .folderNotEmpty: return String(localized: "Move or delete the passwords in this folder first.")
        case .folderNotFound, .entryNotFound: return String(localized: "This item no longer exists.")
        case .authenticationFailed: return String(localized: "Authentication failed.")
        case .corruptedData: return String(localized: "The password database cannot be read.")
        case .duplicateEntry: return String(localized: "This password already exists.")
        case .keychainUnavailable: return String(localized: "The macOS Keychain is unavailable.")
        case .databaseNotConfigured: return String(localized: "Create the password database first.")
        case .vaultLocked: return String(localized: "Unlock the password database first.")
        case .wrongMasterPassword: return String(localized: "The database password is incorrect.")
        case .unsupportedFormat: return String(localized: "This password database format is not supported.")
        case .cloudUnavailable: return String(localized: "OneDrive sync needs attention")
        case .externalConflict: return String(localized: "Password database changes need conflict recovery.")
        case .saveFailed: return String(localized: "The password database could not be saved.")
        case .invalidAutoLockInterval: return String(localized: "Choose a supported automatic lock time.")
        case .userCancelled: return ""
        }
    }

    private func passwordVaultFailureMessage(_ stateCode: String) -> String {
        switch stateCode {
        case "corrupted": return passwordVaultMessage(.corruptedData)
        case "save": return passwordVaultMessage(.saveFailed)
        default: return String(localized: "Password Vault Unavailable")
        }
    }

    private func makeFolderShortcutEditorView(for folderID: SnippetFolder.ID, keyCombo: KeyCombo?) -> NSView {
        let view = MainMenuFolderShortcutEditorView(
            keyCombo: keyCombo,
            onChange: { [weak self] keyCombo in
                self?.recordFolderShortcut(keyCombo)
            },
            onClear: { [weak self] in
                self?.clearFolderShortcut(folderID)
            }
        )
        folderShortcutEditorView = view
        return view
    }

    private func enabledSnippetFolderDetails() -> [SnippetFolderDetail] {
        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = snippetDataSource?.fetchFolderDetails().filter { $0.folder.isEnabled } ?? []
        guard !query.isEmpty else { return details }
        return details.filter { detail in
            detail.folder.title.localizedCaseInsensitiveContains(query) ||
                detail.snippets.contains {
                    $0.isEnabled &&
                        ($0.title.localizedCaseInsensitiveContains(query) ||
                         $0.content.localizedCaseInsensitiveContains(query))
                }
        }
    }

    private func enabledSnippets(in detail: SnippetFolderDetail, folderTitleMatches: Bool = false) -> [Snippet] {
        let snippets = detail.snippets.filter(\.isEnabled)
        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !folderTitleMatches else { return snippets }
        return snippets.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    private func emptyRow(title: String) -> EmbeddedRow {
        EmbeddedRow(
            title: title,
            view: MainMenuEmbeddedEmptyRowView(title: title),
            confirm: {}
        )
    }

    private func noticeItems() -> [MainMenuPanelItem] {
        itemsProvider().filter { item in
            switch item {
            case .notice, .separator:
                return true
            case .snippetFolder, .action:
                return false
            }
        }
    }

    private func resetVisibleRows() {
        visibleHistoryIDs.removeAll()
        visibleSnippetFolderIDs.removeAll()
        visibleSnippetIDs.removeAll()
        visiblePasswordVaultFolderIDs.removeAll()
        visiblePasswordVaultEntryIDs.removeAll()
        visibleMainMenuRowTitles.removeAll()
        currentSnippetFolderTitle = nil
    }

    private func addEmbeddedHeader(_ content: EmbeddedContent, frame: NSRect) {
        let supportsWorkspaceEditing = selectedMode == .snippets
            || (selectedMode == .passwordVault
                && passwordVaultPage == .vault
                && passwordVaultDataSource?.state() == .unlocked)
        let header = MainMenuEmbeddedHeaderView(
            frame: frame,
            title: content.headerTitle,
            subtitle: content.headerSubtitle,
            showsBackButton: content.showsBackButton,
            canGoToPreviousPage: content.canGoToPreviousPage,
            canGoToNextPage: content.canGoToNextPage,
            typeFilter: content.typeFilter,
            showsEditButton: supportsWorkspaceEditing,
            isEditing: isWorkspaceEditing,
            onBack: { [weak self] in self?.handleEmbeddedBack() },
            onPreviousPage: { [weak self] in self?.goToPreviousHistoryPage() },
            onNextPage: { [weak self] in self?.goToNextHistoryPage() },
            onTypeFilter: { [weak self] typeFilter in self?.updateHistoryTypeFilter(typeFilter) },
            onToggleEditing: { [weak self] in self?.toggleWorkspaceEditing() }
        )
        contentView.addSubview(header)
    }

    private func handleEmbeddedBack() {
        if selectedMode == .passwordVault, passwordVaultPage != .vault {
            returnFromPasswordVaultContextPage()
            return
        }
        returnToSnippetFolders()
    }

    private func toggleWorkspaceEditing() {
        isWorkspaceEditing.toggle()
        if !isWorkspaceEditing {
            inlineEditorState = nil
            passwordVaultEditorState = nil
            passwordVaultFolderEditorState = nil
        }
        reloadContentKeepingTopLeft()
    }

    private func draggedID(_ payload: String, prefix: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }

    private func reorderedIDs<ID: Equatable>(_ ids: [ID], moving source: ID, around target: ID, after: Bool) -> [ID]? {
        guard source != target, ids.contains(source), let targetIndex = ids.firstIndex(of: target) else { return nil }
        var result = ids.filter { $0 != source }
        let adjustedTargetIndex = result.firstIndex(of: target) ?? targetIndex
        result.insert(source, at: min(result.count, adjustedTargetIndex + (after ? 1 : 0)))
        return result
    }

    private func handleSnippetDrop(_ payload: String, onFolder targetID: SnippetFolder.ID, after: Bool) -> Bool {
        guard let rawSourceID = draggedID(payload, prefix: "snippet-folder:") else {
            guard let rawSnippetID = draggedID(payload, prefix: "snippet:") else { return false }
            let snippetID = Snippet.ID(rawValue: rawSnippetID)
            return moveSnippet(snippetID, toFolder: targetID, targetSnippetID: nil, after: true)
        }
        let sourceID = SnippetFolder.ID(rawValue: rawSourceID)
        let ids = enabledSnippetFolderDetails().map(\.folder.id)
        guard let reordered = reorderedIDs(ids, moving: sourceID, around: targetID, after: after),
              snippetDataSource?.reorderFolders(reordered) == true else { return false }
        reloadContentKeepingTopLeft()
        return true
    }

    private func handleSnippetDrop(_ payload: String, onSnippet targetID: Snippet.ID, after: Bool) -> Bool {
        guard let rawSnippetID = draggedID(payload, prefix: "snippet:") else { return false }
        let snippetID = Snippet.ID(rawValue: rawSnippetID)
        guard let targetFolderID = enabledSnippetFolderDetails().first(where: {
            $0.snippets.contains(where: { $0.id == targetID })
        })?.folder.id else { return false }
        return moveSnippet(snippetID, toFolder: targetFolderID, targetSnippetID: targetID, after: after)
    }

    private func moveSnippet(
        _ id: Snippet.ID,
        toFolder folderID: SnippetFolder.ID,
        targetSnippetID: Snippet.ID?,
        after: Bool
    ) -> Bool {
        let details = enabledSnippetFolderDetails()
        var orders = Dictionary(uniqueKeysWithValues: details.map { ($0.folder.id, $0.snippets.map(\.id)) })
        for key in orders.keys { orders[key]?.removeAll { $0 == id } }
        guard var destination = orders[folderID] else { return false }
        if let targetSnippetID, let index = destination.firstIndex(of: targetSnippetID) {
            destination.insert(id, at: index + (after ? 1 : 0))
        } else {
            destination.append(id)
        }
        orders[folderID] = destination
        guard snippetDataSource?.moveSnippet(id, folderID, orders) == true else { return false }
        expandedSnippetFolderID = folderID
        reloadContentKeepingTopLeft()
        return true
    }

    private func handlePasswordDrop(_ payload: String, onFolder targetID: UUID, after: Bool) -> Bool {
        if let sourceID = draggedID(payload, prefix: "password-folder:") {
            guard let folders = try? passwordVaultDataSource?.fetchFolders(),
                  let reordered = reorderedIDs(folders.map(\.id), moving: sourceID, around: targetID, after: after),
                  let dataSource = passwordVaultDataSource else { return false }
            dataSource.reorderFolders(reordered) { [weak self] result in
                if case .success = result { self?.reloadContentKeepingTopLeft() }
            }
            return true
        }
        guard let entryID = draggedID(payload, prefix: "password-entry:") else { return false }
        return movePasswordEntry(entryID, toFolder: targetID, targetEntryID: nil, after: true)
    }

    private func handlePasswordDrop(_ payload: String, onEntry targetID: UUID, after: Bool) -> Bool {
        guard let entryID = draggedID(payload, prefix: "password-entry:"),
              let entries = try? passwordVaultDataSource?.fetchEntries(),
              let targetFolderID = entries.first(where: { $0.id == targetID })?.folderID else { return false }
        return movePasswordEntry(entryID, toFolder: targetFolderID, targetEntryID: targetID, after: after)
    }

    private func movePasswordEntry(_ id: UUID, toFolder folderID: UUID, targetEntryID: UUID?, after: Bool) -> Bool {
        guard let dataSource = passwordVaultDataSource,
              let folders = try? dataSource.fetchFolders(),
              let entries = try? dataSource.fetchEntries() else { return false }
        var orders = Dictionary(uniqueKeysWithValues: folders.map { folder in
            (folder.id, entries.filter { $0.folderID == folder.id }.map(\.id))
        })
        for key in orders.keys { orders[key]?.removeAll { $0 == id } }
        guard var destination = orders[folderID] else { return false }
        if let targetEntryID, let index = destination.firstIndex(of: targetEntryID) {
            destination.insert(id, at: index + (after ? 1 : 0))
        } else {
            destination.append(id)
        }
        orders[folderID] = destination
        dataSource.moveEntry(id, folderID, orders) { [weak self] result in
            if case .success = result {
                self?.expandedPasswordVaultFolderID = folderID
                self?.reloadContentKeepingTopLeft()
            }
        }
        return true
    }

    private func addToolbar(at verticalPosition: CGFloat) {
        addToolbar(frame: NSRect(
            x: 0,
            y: verticalPosition,
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.toolbarHeight
        ))
    }

    private func addToolbar(frame: NSRect) {
        let toolbar = MainMenuToolbarView(
            frame: frame,
            configuration: MainMenuToolbarViewConfiguration(
                selectedMode: {
                    switch selectedMode {
                    case .history: return .history
                    case .snippets: return .snippets
                    case .passwordVault: return .passwordVault
                    }
                }(),
                oneDriveStatus: oneDriveStatusService.currentStatus(),
                passwordVaultSyncSnapshot: passwordVaultSyncDataSource?.snapshot()
            ),
            actions: MainMenuToolbarActions(
                onSearch: { [weak self] in self?.toggleSearchField() },
                onHistory: { [weak self] in self?.openHistoryFromToolbar() },
                onSnippets: { [weak self] in self?.openSnippetsFromToolbar() },
                onPasswordVault: { [weak self] in self?.openPasswordVaultFromToolbar() },
                onOneDrive: { [weak self] in self?.openOneDriveFromToolbar() },
                onPreferences: { [weak self] in
                    guard let self, self.close() else { return }
                    self.onOpenPreferences()
                }
            )
        )
        contentView.addSubview(toolbar)
        oneDriveStatusButton = toolbar.oneDriveStatusButton
    }

    private func updateEmbeddedSearchLayout() {
        guard usesEmbeddedContent else { return }
        applyCurrentContentSizeKeepingTopLeft()
        guard let headerBlock = firstSubview(identifier: "mainMenuHeaderBlock", in: contentView),
              let contentBlock = firstSubview(identifier: "mainMenuContentBlock", in: contentView),
              let footerDock = firstSubview(identifier: "mainMenuFooterDock", in: contentView) else {
            reloadContentKeepingTopLeft()
            return
        }

        headerBlock.frame = headerBlockFrame
        contentBlock.frame = contentBlockFrame
        updateEmbeddedScrollFrame(in: contentBlock)
        footerDock.frame = footerDockFrame
        if let searchFieldFrame {
            addSearchField(frame: searchFieldFrame)
        } else {
            searchField.removeFromSuperview()
        }
    }

    private func updateEmbeddedScrollFrame(in contentBlock: NSView) {
        guard let scrollView = contentBlock.subviews.compactMap({ $0 as? NSScrollView }).first else { return }
        let scrollFrame = contentBlock.bounds.insetBy(
            dx: MainMenuPanelLayout.contentInnerPadding,
            dy: MainMenuPanelLayout.contentInnerPadding
        )
        scrollView.frame = scrollFrame
        if let documentView = scrollView.documentView {
            documentView.frame.size.width = scrollFrame.width
            documentView.subviews.forEach { $0.frame.size.width = scrollFrame.width }
            let topOffset = max(0, documentView.frame.height - scrollFrame.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: topOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func firstSubview(identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = firstSubview(identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    private func addSearchField(at verticalPosition: CGFloat) {
        addSearchField(frame: NSRect(
            x: MainMenuPanelLayout.toolbarHorizontalInset,
            y: verticalPosition + 1,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.toolbarHorizontalInset * 2,
            height: MainMenuPanelLayout.searchHeight - 2
        ))
    }

    private func addSearchField(frame: NSRect) {
        let hasActiveEditor = searchField.currentEditor() != nil
        searchField.identifier = NSUserInterfaceItemIdentifier("mainMenuSearchField")
        searchField.placeholderString = String(localized: "Search...")
        searchField.font = .systemFont(ofSize: 12, weight: .regular)
        searchField.controlSize = .regular
        searchField.focusRingType = .default
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        let query = currentSearchQuery()
        if !hasActiveEditor || searchField.stringValue != query {
            searchField.stringValue = query
        }
        searchField.frame = frame
        if searchField.superview !== contentView {
            searchField.removeFromSuperview()
            contentView.addSubview(searchField, positioned: .above, relativeTo: nil)
        }
    }

    @objc private func searchFieldAction(_ sender: NSSearchField) {
        guard !searchFieldHasMarkedText else { return }
        searchQueryChangeTimer?.invalidate()
        emitSearchQueryChangeIfReady()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField, field === searchField else { return }
        guard !searchFieldHasMarkedText else { return }
        scheduleSearchQueryChange()
    }

    private func scheduleSearchQueryChange() {
        searchQueryChangeTimer?.invalidate()
        searchQueryChangeTimer = Timer.scheduledTimer(
            withTimeInterval: searchQueryDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.emitSearchQueryChangeIfReady()
        }
    }

    private func emitSearchQueryChangeIfReady() {
        searchQueryChangeTimer?.invalidate()
        searchQueryChangeTimer = nil
        guard isSearchVisible, !searchFieldHasMarkedText else { return }
        updateSearchQuery(searchField.stringValue)
    }

    private var searchFieldHasMarkedText: Bool {
#if DEBUG
        if let mainMenuSearchMarkedTextStateProviderForTesting {
            return mainMenuSearchMarkedTextStateProviderForTesting()
        }
#endif
        guard let editor = searchField.currentEditor() as? NSTextView else { return false }
        return editor.hasMarkedText()
    }

    private var searchFieldHasActiveEditor: Bool {
        isSearchVisible && searchField.currentEditor() != nil
    }

    private func currentSearchQuery() -> String {
        switch selectedMode {
        case .history:
            return historyDataSource?.currentState().query ?? ""
        case .snippets:
            return snippetSearchQuery
        case .passwordVault:
            return passwordVaultSearchQuery
        }
    }

    private func updateSearchQuery(_ query: String) {
        guard usesEmbeddedContent else { return }
        editingFolderShortcutID = nil
        switch selectedMode {
        case .history:
            historyDataSource?.updateState { $0.updateQuery(query) }
        case .snippets:
            snippetSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        case .passwordVault:
            passwordVaultSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        reloadContentKeepingTopLeft()
        if searchField.superview != nil, searchField.currentEditor() == nil {
            panel?.makeFirstResponder(searchField)
        }
    }

    private func reloadContentKeepingTopLeft() {
        let topLeftPoint = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        reloadContent()
        if let topLeftPoint {
            panel?.setFrameTopLeftPoint(topLeftPoint)
        }
    }

    private func updateOneDriveStatusButton(_ status: OneDriveProcessStatus) {
        if let oneDriveStatusButton {
            if let snapshot = passwordVaultSyncDataSource?.snapshot() {
                oneDriveStatusButton.configure(snapshot: snapshot, processStatus: status)
            } else {
                oneDriveStatusButton.configure(status: status)
            }
        } else {
            reloadContentIfVisible()
        }
    }

    private func addSeparator(at verticalPosition: CGFloat) {
        let separator = makeSeparatorView(width: MainMenuPanelLayout.width)
        separator.frame.origin.y = verticalPosition
        contentView.addSubview(separator)
    }

    private func makeSeparatorView(width: CGFloat) -> NSView {
        let separator = NSView(frame: NSRect(
            x: MainMenuPanelLayout.separatorHorizontalInset,
            y: 0,
            width: width - MainMenuPanelLayout.separatorHorizontalInset * 2,
            height: MainMenuPanelLayout.separatorHeight
        ))
        separator.identifier = NSUserInterfaceItemIdentifier("mainMenuSeparator")
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: MainMenuPanelLayout.separatorAlpha).cgColor
        return separator
    }

    private func position(_ panel: NSPanel, near screenPoint: NSPoint) {
        let visibleFrame = NSScreen.screens
            .first { $0.frame.contains(screenPoint) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let originX = min(
            max(screenPoint.x - MainMenuPanelLayout.width / 2, visibleFrame.minX + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxX - MainMenuPanelLayout.width - MainMenuPanelLayout.screenPadding
        )
        let originY = min(
            max(screenPoint.y - panel.frame.height, visibleFrame.minY + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxY - panel.frame.height - MainMenuPanelLayout.screenPadding
        )
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func position(_ panel: NSPanel, anchoredTo menuFrame: NSRect) {
        panel.setFrameTopLeftPoint(NSPoint(x: menuFrame.minX, y: menuFrame.maxY))
    }

    private func position(_ panel: NSPanel, attachedToStatusItemFrame statusItemFrame: NSRect) {
        let visibleFrame = NSScreen.screens
            .first { $0.frame.intersects(statusItemFrame) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let originX = min(
            max(statusItemFrame.midX - panel.frame.width / 2, visibleFrame.minX + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxX - panel.frame.width - MainMenuPanelLayout.screenPadding
        )
        let topY = statusItemFrame.minY
        panel.setFrameTopLeftPoint(NSPoint(x: originX, y: topY))
    }

    func reloadOneDriveStatusIfVisible() {
        guard panel?.isVisible == true else { return }
        refreshPasswordVaultSyncPresentationIfVisible()
    }

    func refreshPasswordVaultSyncPresentationIfVisible(
        snapshot: PasswordVaultSyncSnapshot? = nil
    ) {
        guard panel?.isVisible == true else { return }
        let processStatus = oneDriveStatusService.currentStatus()
        let resolvedSnapshot = snapshot ?? passwordVaultSyncDataSource?.snapshot()
        if let resolvedSnapshot, let oneDriveStatusButton {
            oneDriveStatusButton.configure(snapshot: resolvedSnapshot, processStatus: processStatus)
        } else {
            updateOneDriveStatusButton(processStatus)
        }
        guard let resolvedSnapshot else { return }
        if case .failed(.remoteCredentialsRequired) = resolvedSnapshot.phase {
            // Keep the user's explicit Back choice stable until sync produces a different state.
        } else {
            passwordVaultSuppressesRemotePrompt = false
        }
        if selectedMode == .passwordVault,
           passwordVaultPage == .vault,
           !passwordVaultSuppressesRemotePrompt,
           case .failed(.remoteCredentialsRequired) = resolvedSnapshot.phase {
            passwordVaultPage = .remoteCredentials
            reloadContentKeepingTopLeft()
        }
    }

    private func showSearchField() {
        guard commitInlineEditorFromCurrentDraft() else { return }
        editingFolderShortcutID = nil
        isWorkspaceEditing = false
        guard !isSearchVisible else {
            panel?.makeFirstResponder(searchField)
            return
        }
        isSearchVisible = true
        if usesEmbeddedContent {
            updateEmbeddedSearchLayout()
        } else {
            addSearchField(at: fixedSearchY)
        }
        panel?.makeFirstResponder(searchField)
    }

    private func toggleSearchField() {
        if isSearchVisible {
            hideSearchField()
        } else {
            showSearchField()
        }
    }

    private func hideSearchField() {
        guard isSearchVisible else { return }
        searchQueryChangeTimer?.invalidate()
        searchQueryChangeTimer = nil
        isSearchVisible = false
        searchField.removeFromSuperview()
        panel?.makeFirstResponder(nil)
        if usesEmbeddedContent {
            updateEmbeddedSearchLayout()
        }
    }

    private func openOneDriveFromToolbar() {
        switch oneDriveStatusService.currentStatus() {
        case .running:
            if oneDriveStatusService.isMainApplicationRunning() {
                guard close() else { return }
                onOpenOneDriveStatus()
            } else {
                _ = oneDriveStatusService.openOneDrive()
            }
        case .notRunning:
            _ = oneDriveStatusService.openOneDrive()
        case .notInstalled:
            break
        }
    }

    private func returnFromPasswordVaultContextPage() {
        switch passwordVaultPage {
        case .remoteCredentials:
            passwordVaultRemoteCredentialsView?.clearSecret()
            passwordVaultRemoteCredentialsView = nil
            passwordVaultSuppressesRemotePrompt = true
            passwordVaultPage = .vault
        case .conflictSummary:
            passwordVaultPage = .vault
        case .localCopyRecovery where passwordVaultLocalRecoveryShowsWarning:
            passwordVaultLocalRecoveryShowsWarning = false
        case .localCopyRecovery:
            return
        case .vault:
            return
        }
        passwordVaultInlineActionView = nil
        reloadContentKeepingTopLeft()
    }

    private func openHistoryFromToolbar() {
        openHistoryFromMainMenu()
    }

    private func openSnippetsFromToolbar() {
        openSnippetsFromMainMenu()
    }

    private func openPasswordVaultFromToolbar() {
        openPasswordVaultFromMainMenu()
    }

    private func expandSnippetFolder(_ folderID: SnippetFolder.ID) {
        editingFolderShortcutID = nil
        expandedSnippetFolderID = folderID
        reloadContentKeepingTopLeft()
        selectSnippetFolderRowIfVisible(folderID)
    }

    private func toggleSnippetFolder(_ folderID: SnippetFolder.ID) {
        if expandedSnippetFolderID == folderID {
            returnToSnippetFolders()
        } else {
            expandSnippetFolder(folderID)
        }
    }

    private func returnToSnippetFolders() {
        guard selectedMode == .snippets else { return }
        expandedSnippetFolderID = nil
        reloadContentKeepingTopLeft()
    }

    private func selectSnippetFolderRowIfVisible(_ folderID: SnippetFolder.ID) {
        guard let index = keyboardEntries.firstIndex(where: {
            if case let .snippetFolder(id) = $0.role {
                return id == folderID
            }
            return false
        }) else { return }
        selectKeyboardEntry(at: index, triggerChildPanel: false)
    }

    private func selectSnippetRowIfVisible(_ snippetID: Snippet.ID) {
        guard let index = keyboardEntries.firstIndex(where: {
            if case let .snippet(id) = $0.role {
                return id == snippetID
            }
            return false
        }) else { return }
        selectKeyboardEntry(at: index, triggerChildPanel: false)
    }

    private func expandSelectedSnippetFolder() -> Bool {
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex),
              case let .snippetFolder(folderID) = keyboardEntries[selectedKeyboardEntryIndex].role else {
            return false
        }
        expandSnippetFolder(folderID)
        return true
    }

    private func selectExpandedSnippetFolderFromSnippetRow() -> Bool {
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex),
              case .snippet = keyboardEntries[selectedKeyboardEntryIndex].role,
              let expandedSnippetFolderID else {
            return false
        }
        selectSnippetFolderRowIfVisible(expandedSnippetFolderID)
        return true
    }

    private func confirmHistorySelection(_ historyID: PasteboardHistory.ID) {
        let targetContext = pasteTargetContext
        close()
        historyDataSource?.selectHistory(historyID, targetContext)
    }

    private func confirmSnippetSelection(_ snippetID: Snippet.ID) {
        let targetContext = pasteTargetContext
        close()
        snippetDataSource?.selectSnippet(snippetID, targetContext)
    }

    private func confirmDeleteSnippetFolder(_ folderID: SnippetFolder.ID) {
        guard inlineEditorState == nil,
              let detail = snippetDataSource?.fetchFolderDetails().first(where: { $0.folder.id == folderID }) else {
            return
        }
        let snippetCount = detail.snippets.count
        let snippetCountText = snippetCount == 1 ? "1 snippet" : "\(snippetCount) snippets"
        let result = deleteConfirmationRunner(PasteraConfirmationOptions(
            title: String(localized: "Delete Folder"),
            message: String(localized: "Delete \"\(detail.folder.title)\" and its \(snippetCountText)? This cannot be undone."),
            confirmTitle: String(localized: "Delete Folder"),
            cancelTitle: String(localized: "Cancel"),
            isDestructive: true
        ), panel)
        guard result.confirmed else { return }

        snippetDataSource?.deleteFolder(folderID)
        if expandedSnippetFolderID == folderID {
            expandedSnippetFolderID = nil
        }
        reloadContentKeepingTopLeft()
        if let expandedSnippetFolderID {
            selectSnippetFolderRowIfVisible(expandedSnippetFolderID)
        }
    }

    private func confirmDeleteSnippet(_ snippetID: Snippet.ID) {
        guard inlineEditorState == nil,
              let context = snippetContext(for: snippetID) else {
            return
        }
        let result = deleteConfirmationRunner(PasteraConfirmationOptions(
            title: String(localized: "Delete Snippet"),
            message: String(localized: "Delete \"\(context.snippet.title)\" from \"\(context.detail.folder.title)\"? This cannot be undone."),
            confirmTitle: String(localized: "Delete Snippet"),
            cancelTitle: String(localized: "Cancel"),
            isDestructive: true
        ), panel)
        guard result.confirmed else { return }

        snippetDataSource?.deleteSnippet(snippetID)
        expandedSnippetFolderID = context.detail.folder.id
        reloadContentKeepingTopLeft()
        selectSnippetRowAfterDeletion(folderID: context.detail.folder.id, deletedIndex: context.index)
    }

    private func snippetContext(
        for snippetID: Snippet.ID
    ) -> (detail: SnippetFolderDetail, snippet: Snippet, index: Int)? {
        for detail in snippetDataSource?.fetchFolderDetails() ?? [] {
            guard let index = detail.snippets.firstIndex(where: { $0.id == snippetID }) else { continue }
            return (detail, detail.snippets[index], index)
        }
        return nil
    }

    private func selectSnippetRowAfterDeletion(folderID: SnippetFolder.ID, deletedIndex: Int) {
        guard let detail = enabledSnippetFolderDetails().first(where: { $0.folder.id == folderID }) else { return }
        let query = snippetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderTitleMatches = !query.isEmpty && detail.folder.title.localizedCaseInsensitiveContains(query)
        let snippets = enabledSnippets(in: detail, folderTitleMatches: folderTitleMatches)
        guard let snippet = snippets[safe: min(deletedIndex, snippets.count - 1)] else {
            selectSnippetFolderRowIfVisible(folderID)
            return
        }
        selectSnippetRowIfVisible(snippet.id)
    }

    private func goToPreviousHistoryPage() {
        guard selectedMode == .history else { return }
        guard (historyDataSource?.currentState().pageIndex ?? 0) > 0 else { return }
        historyDataSource?.updateState { $0.goToPreviousPage() }
        reloadContentKeepingTopLeft()
    }

    private func goToNextHistoryPage() {
        guard selectedMode == .history, let historyDataSource else { return }
        let page = historyDataSource.fetchPage()
        historyDataSource.updateState { $0.goToNextPage(if: page.hasNextPage) }
        reloadContentKeepingTopLeft()
    }

    private func updateHistoryTypeFilter(_ typeFilter: HistoryMenuTypeFilter) {
        guard selectedMode == .history else { return }
        guard commitInlineEditorFromCurrentDraft() else { return }
        historyDataSource?.updateState { $0.updateTypeFilter(typeFilter) }
        reloadContentKeepingTopLeft()
    }

    private func numericShortcutText(forRowIndex index: Int) -> String? {
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        return PasteraShortcutFormatter.numericString(forRowIndex: index, startsAtZero: startsAtZero)
    }

    private func confirmNumberShortcut(_ event: NSEvent) -> Bool {
        guard usesEmbeddedContent else { return false }
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        switch selectedMode {
        case .history:
            guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
                for: event,
                startsAtZero: startsAtZero,
                rowCount: visibleHistoryIDs.count
            ) else { return false }
            confirmHistorySelection(visibleHistoryIDs[rowIndex])
            return true
        case .snippets:
            if expandedSnippetFolderID == nil {
                guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
                    for: event,
                    startsAtZero: startsAtZero,
                    rowCount: visibleSnippetFolderIDs.count
                ) else { return false }
                expandSnippetFolder(visibleSnippetFolderIDs[rowIndex])
                return true
            }
            guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
                for: event,
                startsAtZero: startsAtZero,
                rowCount: visibleSnippetIDs.count
            ) else { return false }
            confirmSnippetSelection(visibleSnippetIDs[rowIndex])
            return true
        case .passwordVault:
            guard passwordVaultPage == .vault,
                  passwordVaultEditorState == nil,
                  passwordVaultFolderEditorState == nil else { return false }
            switch passwordVaultDataSource?.state() {
            case .unlocked, .readOnlyWarning:
                break
            default:
                return false
            }
            if expandedPasswordVaultFolderID == nil && passwordVaultSearchQuery.isEmpty {
                guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
                    for: event,
                    startsAtZero: startsAtZero,
                    rowCount: visiblePasswordVaultFolderIDs.count
                ) else { return false }
                togglePasswordVaultFolder(visiblePasswordVaultFolderIDs[rowIndex])
                return true
            }
            guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
                for: event,
                startsAtZero: startsAtZero,
                rowCount: visiblePasswordVaultEntryIDs.count,
                allowedModifierFlags: .control
            ) else { return false }
            let entryID = visiblePasswordVaultEntryIDs[rowIndex]
            if event.modifierFlags.contains(.control) {
                pastePasswordVaultUsername(entryID)
            } else {
                pastePasswordVaultPassword(entryID)
            }
            return true
        }
    }
}

extension MainMenuPanelController {
    func handleKeyboardNavigationFromChild(_ event: NSEvent) -> Bool {
        handleKeyboardNavigation(event)
    }

    fileprivate func handleKeyboardNavigation(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }
        if handleFolderShortcutEditorKey(event) {
            return true
        }
        if handleInlineEditorKey(event) {
            return true
        }
        if inlineEditorState != nil {
            return false
        }
        if searchFieldHasMarkedText {
            return false
        }
        if handleSearchEscape(event) {
            return true
        }
        if isPreferencesShortcut(event) {
            onOpenPreferences()
            return true
        }
        if isSearchShortcut(event) {
            showSearchField()
            return true
        }
        if searchFieldHasActiveEditor {
            return false
        }
        if confirmNumberShortcut(event) {
            return true
        }
        if handleSnippetDeleteShortcut(event) {
            return true
        }
        if usesEmbeddedContent, selectedMode == .snippets {
            switch event.keyCode {
            case 123:
                return selectExpandedSnippetFolderFromSnippetRow()
            case 124:
                return expandSelectedSnippetFolder()
            default:
                break
            }
        }
        let ignoredSystemFlags: NSEvent.ModifierFlags = [.numericPad, .function]
        let navigationFlags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(ignoredSystemFlags)
        if usesEmbeddedContent, selectedMode == .history, navigationFlags.isEmpty {
            switch event.keyCode {
            case 123:
                goToPreviousHistoryPage()
                return true
            case 124:
                goToNextHistoryPage()
                return true
            default:
                break
            }
        }
        let direction: Int
        switch event.keyCode {
        case 125:
            direction = 1
        case 126:
            direction = -1
        case 36, 49, 76:
            guard let selectedKeyboardEntryIndex,
                  keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else { return false }
            keyboardEntries[selectedKeyboardEntryIndex].confirm()
            return true
        default:
            return false
        }
        guard !keyboardEntries.isEmpty else { return false }

        let currentIndex: Int
        if let selectedKeyboardEntryIndex {
            currentIndex = selectedKeyboardEntryIndex
        } else {
            currentIndex = direction > 0 ? -1 : keyboardEntries.count
        }

        let nextIndex = min(max(currentIndex + direction, 0), keyboardEntries.count - 1)
        selectKeyboardEntry(at: nextIndex, triggerChildPanel: true)
        return true
    }

    private func handleInlineEditorKey(_ event: NSEvent) -> Bool {
        guard inlineEditorState != nil else { return false }
        if event.keyCode == 53 {
            discardInlineEditor()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        if flags.contains(.command) {
            _ = commitInlineEditorFromCurrentDraft()
            return true
        }
        if inlineEditorView?.shouldCommitPlainReturn == true {
            _ = commitInlineEditorFromCurrentDraft()
            return true
        }
        return false
    }

    private func handleFolderShortcutEditorKey(_ event: NSEvent) -> Bool {
        guard editingFolderShortcutID != nil else { return false }
        if event.keyCode == 53 {
            discardFolderShortcutEditor()
            return true
        }
        return false
    }

    private func handleSnippetDeleteShortcut(_ event: NSEvent) -> Bool {
        guard inlineEditorState == nil,
              editingFolderShortcutID == nil,
              usesEmbeddedContent,
              selectedMode == .snippets,
              isCommandDeleteShortcut(event),
              let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else {
            return false
        }

        switch keyboardEntries[selectedKeyboardEntryIndex].role {
        case let .snippetFolder(folderID):
            confirmDeleteSnippetFolder(folderID)
            return true
        case let .snippet(snippetID):
            confirmDeleteSnippet(snippetID)
            return true
        case .none, .passwordEntry:
            return false
        }
    }

    private func isCommandDeleteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)
        return flags == .command && event.charactersIgnoringModifiers?.lowercased() == "d"
    }

    private func isSearchShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 3 && flags.contains(.command)
    }

    private func isPreferencesShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)
        return event.type == .keyDown
            && flags == .command
            && event.charactersIgnoringModifiers == ","
    }

    private func handleSearchEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, isSearchVisible else { return false }
        if currentSearchQuery().isEmpty {
            hideSearchField()
        } else {
            searchField.stringValue = ""
            updateSearchQuery("")
        }
        return true
    }

    @discardableResult
    fileprivate func appendKeyboardEntry(
        title: String,
        view: NSView,
        openChildPanel: (() -> Void)?,
        role: KeyboardEntryRole = .none,
        confirm: @escaping () -> Void
    ) -> Int {
        let index = keyboardEntries.count
        keyboardEntries.append(KeyboardEntry(
            title: title,
            role: role,
            view: { [weak view] in view },
            setSelected: { [weak view] selected in
                if let headerView = view as? MainMenuHeaderItemView {
                    headerView.setKeyboardSelected(selected)
                } else if let rowView = view as? MainMenuPanelRowView {
                    rowView.setKeyboardSelected(selected)
                } else if selected, let rowView = view as? HistoryMenuRowView {
                    rowView.window?.makeFirstResponder(rowView)
                } else if let rowView = view as? MainMenuEmbeddedEmptyRowView {
                    rowView.setKeyboardSelected(selected)
                }
                if selected, let view {
                    view.scrollToVisible(view.bounds)
                }
            },
            openChildPanel: openChildPanel,
            confirm: confirm
        ))
        return index
    }

    fileprivate func selectKeyboardEntry(at index: Int, triggerChildPanel: Bool) {
        guard keyboardEntries.indices.contains(index) else { return }
        if let selectedKeyboardEntryIndex,
           selectedKeyboardEntryIndex != index,
           keyboardEntries.indices.contains(selectedKeyboardEntryIndex) {
            keyboardEntries[selectedKeyboardEntryIndex].setSelected(false)
        }
        selectedKeyboardEntryIndex = index
        keyboardEntries[index].setSelected(true)
        if case .passwordEntry = keyboardEntries[index].role {
            showPasswordVaultQuickActionsCoachmarkIfNeeded()
        }
        if triggerChildPanel {
            keyboardEntries[index].openChildPanel?()
        }
    }

    private func showPasswordVaultQuickActionsCoachmarkIfNeeded() {
        guard selectedMode == .passwordVault,
              !isWorkspaceEditing,
              passwordVaultQuickActionsCoachmarkView == nil,
              !AppEnvironment.current.defaults.bool(
                forKey: Constants.UserDefaults.passwordVaultQuickActionsCoachmarkShown
              ),
              let surface = firstSubview(identifier: "mainMenuContentBlock", in: contentView) else { return }

        AppEnvironment.current.defaults.set(
            true,
            forKey: Constants.UserDefaults.passwordVaultQuickActionsCoachmarkShown
        )
        let coachmark = PasswordVaultQuickActionsCoachmarkView(
            title: String(localized: "Quick paste is available here")
        )
        let width = min(surface.bounds.width - 20, coachmark.preferredWidth)
        coachmark.frame = NSRect(x: (surface.bounds.width - width) / 2, y: 10, width: width, height: 28)
        coachmark.alphaValue = 1
        surface.addSubview(coachmark, positioned: .above, relativeTo: nil)
        passwordVaultQuickActionsCoachmarkView = coachmark

        passwordVaultQuickActionsCoachmarkWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak coachmark] in
            guard let coachmark else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                coachmark.animator().alphaValue = 0
            } completionHandler: { [weak self, weak coachmark] in
                coachmark?.removeFromSuperview()
                if self?.passwordVaultQuickActionsCoachmarkView === coachmark {
                    self?.passwordVaultQuickActionsCoachmarkView = nil
                }
            }
        }
        passwordVaultQuickActionsCoachmarkWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private final class MainMenuSurfaceView: NSView {
    init(frame frameRect: NSRect, identifier: String) {
        super.init(frame: frameRect)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
    }

    required init?(coder: NSCoder) { nil }
}

private final class MainMenuCenteredLabelCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let heightDelta = drawingRect.height - textSize.height
        if heightDelta > 0 {
            drawingRect.origin.y += heightDelta / 2
            drawingRect.size.height = textSize.height
        }
        return drawingRect
    }
}

private final class MainMenuCenteredLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        cell = MainMenuCenteredLabelCell(textCell: "")
    }

    required init?(coder: NSCoder) { nil }
}

private final class MainMenuTypeFilterButton: NSButton {
    var isCurrent = false
    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    func updateAppearance() {
        let background: NSColor
        if isCurrent {
            background = MainMenuVisualColors.accentFill
        } else if isHovered {
            background = MainMenuVisualColors.hoveredRow
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
        contentTintColor = isCurrent ? .controlAccentColor : .labelColor
    }
}

private final class MainMenuEmbeddedHeaderView: NSView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 9
        static let buttonHeight: CGFloat = 26
        static let navButtonWidth: CGFloat = 22
        static let typeButtonWidth: CGFloat = 21
        static let typeButtonSpacing: CGFloat = 1
        static let buttonSpacing: CGFloat = 3
        static let titleTrailingSpacing: CGFloat = 6
        static let pageLabelWidth: CGFloat = 36
        static let paginationWidth: CGFloat = 80
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = MainMenuCenteredLabel()
    private let backButton = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private var typeButtons = [MainMenuTypeFilterButton]()
    private let editButton = NSButton()
    private let onBack: () -> Void
    private let onPreviousPage: () -> Void
    private let onNextPage: () -> Void
    private let onTypeFilter: (HistoryMenuTypeFilter) -> Void
    private let onToggleEditing: () -> Void

    init(
        frame frameRect: NSRect,
        title: String,
        subtitle: String?,
        showsBackButton: Bool,
        canGoToPreviousPage: Bool,
        canGoToNextPage: Bool,
        typeFilter: HistoryMenuTypeFilter?,
        showsEditButton: Bool,
        isEditing: Bool,
        onBack: @escaping () -> Void,
        onPreviousPage: @escaping () -> Void,
        onNextPage: @escaping () -> Void,
        onTypeFilter: @escaping (HistoryMenuTypeFilter) -> Void,
        onToggleEditing: @escaping () -> Void
    ) {
        self.onBack = onBack
        self.onPreviousPage = onPreviousPage
        self.onNextPage = onNextPage
        self.onTypeFilter = onTypeFilter
        self.onToggleEditing = onToggleEditing
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("mainMenuHeaderBlock")
        setup(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            canGoToPreviousPage: canGoToPreviousPage,
            canGoToNextPage: canGoToNextPage,
            typeFilter: typeFilter,
            showsEditButton: showsEditButton,
            isEditing: isEditing
        )
    }

    required init?(coder: NSCoder) { nil }

    // swiftlint:disable:next function_parameter_count
    private func setup(
        title: String,
        subtitle: String?,
        showsBackButton: Bool,
        canGoToPreviousPage: Bool,
        canGoToNextPage: Bool,
        typeFilter: HistoryMenuTypeFilter?,
        showsEditButton: Bool,
        isEditing: Bool
    ) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0

        if showsEditButton {
            configureButton(editButton, symbolName: isEditing ? "checkmark" : "pencil", action: #selector(editClicked(_:)))
            editButton.identifier = NSUserInterfaceItemIdentifier("mainMenuWorkspaceEditButton")
            editButton.toolTip = isEditing ? String(localized: "Done") : String(localized: "Edit")
            editButton.setAccessibilityLabel(editButton.toolTip ?? "")
            editButton.frame = NSRect(
                x: bounds.maxX - Metrics.horizontalInset - Metrics.buttonHeight,
                y: bounds.midY - Metrics.buttonHeight / 2,
                width: Metrics.buttonHeight,
                height: Metrics.buttonHeight
            )
            styleNavigationButton(editButton)
            addSubview(editButton)
        }

        configureButton(backButton, symbolName: "chevron.left", action: #selector(backClicked(_:)))
        backButton.isHidden = !showsBackButton
        backButton.frame = NSRect(
            x: Metrics.horizontalInset,
            y: bounds.midY - Metrics.buttonHeight / 2,
            width: Metrics.navButtonWidth,
            height: Metrics.buttonHeight
        )
        addSubview(backButton)

        let titleLeading = showsBackButton
            ? backButton.frame.maxX + Metrics.buttonSpacing
            : Metrics.horizontalInset
        let hasPagination = subtitle != nil || canGoToPreviousPage || canGoToNextPage
        let controlGroupFrame = NSRect(
            x: bounds.maxX - Metrics.horizontalInset - Metrics.paginationWidth,
            y: bounds.midY - Metrics.buttonHeight / 2,
            width: Metrics.paginationWidth,
            height: Metrics.buttonHeight
        )
        let previousButtonFrame = NSRect(
            x: controlGroupFrame.minX,
            y: controlGroupFrame.minY,
            width: Metrics.navButtonWidth,
            height: Metrics.buttonHeight
        )
        let subtitleFrame = NSRect(
            x: previousButtonFrame.maxX,
            y: controlGroupFrame.minY,
            width: Metrics.pageLabelWidth,
            height: Metrics.buttonHeight
        )
        let nextButtonFrame = NSRect(
            x: subtitleFrame.maxX,
            y: controlGroupFrame.minY,
            width: Metrics.navButtonWidth,
            height: Metrics.buttonHeight
        )
        let titleTrailing = hasPagination
            ? previousButtonFrame.minX
            : (showsEditButton ? editButton.frame.minX : bounds.maxX - Metrics.horizontalInset)
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(
            x: titleLeading,
            y: bounds.midY - 9,
            width: typeFilter == nil ? max(48, titleTrailing - titleLeading - Metrics.titleTrailingSpacing) : 0,
            height: 18
        )
        if typeFilter == nil { addSubview(titleLabel) }

        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.textColor = .labelColor
        subtitleLabel.alignment = .center
        subtitleLabel.frame = subtitleFrame

        configureButton(previousButton, symbolName: "chevron.left", action: #selector(previousClicked(_:)))
        previousButton.toolTip = "\(String(localized: "Previous Page")) · ← / ⌃B"
        previousButton.setAccessibilityLabel(previousButton.toolTip ?? "")
        previousButton.isEnabled = canGoToPreviousPage
        previousButton.frame = previousButtonFrame
        styleNavigationButton(previousButton)

        configureButton(nextButton, symbolName: "chevron.right", action: #selector(nextClicked(_:)))
        nextButton.toolTip = "\(String(localized: "Next Page")) · → / ⌃F"
        nextButton.setAccessibilityLabel(nextButton.toolTip ?? "")
        nextButton.isEnabled = canGoToNextPage
        nextButton.frame = nextButtonFrame
        styleNavigationButton(nextButton)

        if let typeFilter {
            configureTypeButtons(selectedFilter: typeFilter, leading: titleLeading, verticalOrigin: controlGroupFrame.minY)
        }
        if hasPagination {
            addSubview(previousButton)
            addSubview(subtitleLabel)
            addSubview(nextButton)
        }
    }

    @objc private func editClicked(_ sender: NSButton) { onToggleEditing() }

    private func configureButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
    }

    private func styleNavigationButton(_ button: NSButton) {
        button.wantsLayer = true
        button.layer?.cornerRadius = min(button.frame.width, button.frame.height) / 2
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = button.isEnabled
            ? MainMenuVisualColors.controlSurface.cgColor
            : NSColor.clear.cgColor
        button.alphaValue = button.isEnabled ? 1 : 0.45
    }

    private func configureTypeButtons(
        selectedFilter: HistoryMenuTypeFilter,
        leading: CGFloat,
        verticalOrigin: CGFloat
    ) {
        for (index, filter) in HistoryMenuTypeFilter.displayCases.enumerated() {
            let button = MainMenuTypeFilterButton(frame: NSRect(
                x: leading + CGFloat(index) * (Metrics.typeButtonWidth + Metrics.typeButtonSpacing),
                y: verticalOrigin,
                width: Metrics.typeButtonWidth,
                height: Metrics.buttonHeight
            ))
            button.identifier = NSUserInterfaceItemIdentifier("mainMenuTypeFilter.\(filter.rawValue)")
            button.tag = filter.rawValue
            button.setButtonType(.momentaryPushIn)
            button.bezelStyle = .inline
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbolName(for: filter), accessibilityDescription: filter.title)
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.masksToBounds = true
            button.isCurrent = filter == selectedFilter
            button.target = self
            button.action = #selector(typeFilterClicked(_:))
            button.toolTip = filter.title
            button.setAccessibilityLabel(filter.title)
            button.setAccessibilityValue(filter == selectedFilter ? String(localized: "Selected") : "")
            button.updateAppearance()
            addSubview(button)
            typeButtons.append(button)
        }
    }

    private func symbolName(for filter: HistoryMenuTypeFilter) -> String {
        switch filter {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .otherFiles: return "ellipsis"
        case .pdf: return "doc.richtext"
        }
    }

    @objc private func backClicked(_ sender: NSButton) {
        onBack()
    }

    @objc private func previousClicked(_ sender: NSButton) {
        onPreviousPage()
    }

    @objc private func nextClicked(_ sender: NSButton) {
        onNextPage()
    }

    @objc private func typeFilterClicked(_ sender: NSButton) {
        guard let filter = HistoryMenuTypeFilter(rawValue: sender.tag) else { return }
        onTypeFilter(filter)
    }

    #if DEBUG
    var typeFilterItemFramesForTesting: [NSRect] { typeButtons.map(\.frame) }
    var selectedTypeFilterTitlesForTesting: [String] {
        typeButtons.filter(\.isCurrent).compactMap(\.toolTip)
    }
    #endif
}

private final class MainMenuInlineEditorTitleField: NSTextField {
    var onDiscard: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onDiscard?()
    }
}

private final class MainMenuInlineEditorTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onDiscard: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDiscard?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76, flags.contains(.command) {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class MainMenuInlineEditorView: NSControl, NSTextFieldDelegate, NSTextViewDelegate {
    struct Configuration {
        let titleValue: String?
        let titlePlaceholder: String?
        let contentValue: String?
        let errorMessage: String?
    }

    private enum Metrics {
        static let inset: CGFloat = 9
        static let gap: CGFloat = 7
        static let fieldHeight: CGFloat = 26
        static let errorHeight: CGFloat = 16
        static let minimumContentHeight: CGFloat = 112
    }

    private let titleField = MainMenuInlineEditorTitleField()
    private let scrollView = NSScrollView()
    private let textView = MainMenuInlineEditorTextView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let showsTitleField: Bool
    private let showsContentField: Bool
    private let onCommit: () -> Void
    private let onDiscard: () -> Void

    var draftTitle: String {
        titleField.stringValue
    }

    var draftContent: String {
        textView.string
    }

    var shouldCommitPlainReturn: Bool {
        guard showsTitleField else { return false }
        return !showsContentField || titleField.currentEditor() != nil || window?.firstResponder === titleField
    }

    var buttonTitlesForTesting: [String] {
        []
    }

    init(
        configuration: Configuration,
        onCommit: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.showsTitleField = configuration.titleValue != nil
        self.showsContentField = configuration.contentValue != nil
        self.onCommit = onCommit
        self.onDiscard = onDiscard
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MainMenuPanelLayout.width,
            height: Self.preferredHeight(for: configuration)
        ))
        setup(configuration: configuration)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()

        let contentWidth = bounds.width - Metrics.inset * 2
        var top = bounds.maxY - Metrics.inset
        let hasError = !errorLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        errorLabel.isHidden = !hasError
        let errorY = Metrics.inset
        errorLabel.frame = NSRect(
            x: Metrics.inset,
            y: errorY,
            width: contentWidth,
            height: hasError ? Metrics.errorHeight : 0
        )
        let fieldBottom = hasError ? errorLabel.frame.maxY + Metrics.gap : Metrics.inset

        if showsTitleField {
            top -= Metrics.fieldHeight
            titleField.frame = NSRect(
                x: Metrics.inset,
                y: top,
                width: contentWidth,
                height: Metrics.fieldHeight
            )
            top -= Metrics.gap
        }

        if showsContentField {
            let contentHeight = max(Metrics.minimumContentHeight, top - fieldBottom)
            scrollView.frame = NSRect(
                x: Metrics.inset,
                y: fieldBottom,
                width: contentWidth,
                height: contentHeight
            )
            textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(contentHeight, textView.frame.height))
            textView.minSize = NSSize(width: 0, height: contentHeight)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
        }
    }

    func updateDraft(title: String?, content: String?) {
        if let title, showsTitleField {
            titleField.stringValue = title
        }
        if let content, showsContentField {
            textView.string = content
        }
    }

    private func setup(configuration: Configuration) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.030).cgColor

        titleField.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorTitleField")
        titleField.stringValue = configuration.titleValue ?? ""
        titleField.placeholderString = configuration.titlePlaceholder
        titleField.font = .systemFont(ofSize: 12, weight: .regular)
        titleField.bezelStyle = .roundedBezel
        titleField.delegate = self
        titleField.target = self
        titleField.action = #selector(titleCommitted(_:))
        titleField.onDiscard = { [weak self] in self?.onDiscard() }
        titleField.isHidden = !showsTitleField
        if showsTitleField {
            addSubview(titleField)
        }

        textView.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorContentTextView")
        textView.string = configuration.contentValue ?? ""
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.045)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.delegate = self
        textView.onCommit = { [weak self] in self?.onCommit() }
        textView.onDiscard = { [weak self] in self?.onDiscard() }
        scrollView.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorContentScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.isHidden = !showsContentField
        if showsContentField {
            addSubview(scrollView)
        }

        errorLabel.identifier = NSUserInterfaceItemIdentifier("mainMenuInlineEditorErrorLabel")
        errorLabel.stringValue = configuration.errorMessage ?? ""
        errorLabel.font = .systemFont(ofSize: 11, weight: .regular)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        addSubview(errorLabel)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.showsTitleField {
                self.window?.makeFirstResponder(self.titleField)
            } else if self.showsContentField {
                self.window?.makeFirstResponder(self.textView)
            }
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        onCommit()
    }

    func textDidEndEditing(_ notification: Notification) {
        onCommit()
    }

    @objc private func titleCommitted(_ sender: NSTextField) {
        onCommit()
    }

    private static func preferredHeight(for configuration: Configuration) -> CGFloat {
        let showsTitleField = configuration.titleValue != nil
        let showsContentField = configuration.contentValue != nil
        let hasError = !(configuration.errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var height = Metrics.inset * 2
        if showsTitleField {
            height += Metrics.fieldHeight
        }
        if showsTitleField && showsContentField {
            height += Metrics.gap
        }
        if showsContentField {
            height += Metrics.minimumContentHeight
        }
        if hasError {
            height += Metrics.gap + Metrics.errorHeight
        }
        return max(MainMenuPanelLayout.rowHeight, height)
    }
}

private final class MainMenuEmbeddedEmptyRowView: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    private var isKeyboardSelected = false
    private var isMouseInside = false
    private var trackingArea: NSTrackingArea?
    var onHoverFocus: (() -> Void)?

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.rowHeight))
        setup(title: title)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        onHoverFocus?()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        updateAppearance()
    }

    func setKeyboardSelected(_ selected: Bool) {
        isKeyboardSelected = selected
        updateAppearance()
    }

    private func setup(title: String) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(
            x: 10,
            y: bounds.midY - 8,
            width: MainMenuPanelLayout.width - 20,
            height: 16
        )
        addSubview(titleLabel)
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isMouseInside || isKeyboardSelected)
            ? MainMenuVisualColors.hoveredRow.cgColor
            : NSColor.clear.cgColor
    }

    #if DEBUG
    var titleForTesting: String? { titleLabel.stringValue }
    #endif
}

private final class PasswordVaultQuickActionsCoachmarkView: NSView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 9
        static let height: CGFloat = 28
    }

    private let titleLabel: NSTextField

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: Metrics.height))
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("passwordVaultQuickActionsCoachmark")
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.96).cgColor
        layer?.borderColor = MainMenuVisualColors.sectionBorder.cgColor
        layer?.borderWidth = 0.5
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        titleLabel.frame = bounds.insetBy(dx: Metrics.horizontalInset, dy: 6)
    }

    var preferredWidth: CGFloat {
        min(210, max(170, titleLabel.attributedStringValue.size().width + Metrics.horizontalInset * 2 + 8))
    }

    #if DEBUG
    var titleForTesting: String { titleLabel.stringValue }
    #endif
}

private final class MainMenuFolderShortcutEditorView: NSView, RecordViewDelegate {
    private enum Metrics {
        static let horizontalInset: CGFloat = 22
        static let labelWidth: CGFloat = 52
        static let recordHeight: CGFloat = 24
        static let clearButtonSize: CGFloat = 20
        static let spacing: CGFloat = 7
    }

    private let label = NSTextField(labelWithString: String(localized: "Shortcut"))
    private let recordView = RecordView(frame: .zero)
    private let clearButton = NSButton()
    private let onChange: (KeyCombo) -> Void
    private let onClear: () -> Void

    init(keyCombo: KeyCombo?, onChange: @escaping (KeyCombo) -> Void, onClear: @escaping () -> Void) {
        self.onChange = onChange
        self.onClear = onClear
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: MainMenuPanelLayout.width,
            height: MainMenuPanelLayout.folderShortcutEditorHeight
        ))
        setup(keyCombo: keyCombo)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self.recordView)
            _ = self.recordView.beginRecording()
        }
    }

    private func setup(keyCombo: KeyCombo?) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail

        recordView.delegate = self
        recordView.keyCombo = keyCombo
        recordView.identifier = NSUserInterfaceItemIdentifier("mainMenuFolderShortcutRecordView")
        PasteraRecordViewStyler.apply(to: recordView)

        clearButton.identifier = NSUserInterfaceItemIdentifier("mainMenuFolderShortcutClearButton")
        clearButton.setButtonType(.momentaryPushIn)
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.toolTip = String(localized: "Clear Shortcut")
        clearButton.setAccessibilityLabel(String(localized: "Clear Shortcut"))
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked(_:))

        [label, recordView, clearButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: Metrics.labelWidth),

            recordView.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: Metrics.spacing),
            recordView.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordView.heightAnchor.constraint(equalToConstant: Metrics.recordHeight),

            clearButton.leadingAnchor.constraint(equalTo: recordView.trailingAnchor, constant: Metrics.spacing),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: Metrics.clearButtonSize),
            clearButton.heightAnchor.constraint(equalToConstant: Metrics.clearButtonSize)
        ])
    }

    @objc private func clearButtonClicked(_ sender: NSButton) {
        onClear()
    }

    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let keyCombo else {
            onClear()
            return
        }
        onChange(keyCombo)
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}

    #if DEBUG
    func recordKeyComboForTesting(_ keyCombo: KeyCombo) {
        onChange(keyCombo)
    }

    func clearForTesting() {
        onClear()
    }
    #endif
}

private final class MainMenuActionButton: NSButton {
    var onAction: (() -> Void)?

    func connectAction() {
        target = self
        action = #selector(clicked(_:))
    }

    @objc private func clicked(_ sender: NSButton) { onAction?() }
}

#if DEBUG
struct PasswordVaultAccessLayoutSnapshot {
    let title: String
    let fieldLabel: String
    let explanation: String
    let titleFontSize: CGFloat
    let verticalGapFromFieldToButton: CGFloat
    let primaryButtonWidth: CGFloat
    let controlsFitBounds: Bool
    let explanationWrapsWithoutTruncation: Bool
}
#endif

// swiftlint:disable:next type_body_length
private final class PasswordVaultAccessView: NSView, NSTextFieldDelegate {
    enum Mode: Equatable { case create, unlock }

    private let mode: Mode
    private var storageMode: PasswordVaultCreateStorageMode
    private let passwordField = NSSecureTextField()
    private let confirmationField = NSSecureTextField()
    private let visiblePasswordField = NSTextField()
    private let visibleConfirmationField = NSTextField()
    private let passwordVisibilityButton = NSButton()
    private let confirmationVisibilityButton = NSButton()
    private let passwordLabel = NSTextField(labelWithString: String(localized: "Master Password"))
    private let confirmationLabel = NSTextField(labelWithString: String(localized: "Enter Again"))
    private let errorLabel = NSTextField(labelWithString: "")
    private let titleLabel: NSTextField
    private let explanationLabel: NSTextField
    private let storageLabel = NSTextField(labelWithString: String(localized: "Storage"))
    private let localOnlyButton = NSButton(
        radioButtonWithTitle: String(localized: "Keep on This Mac"),
        target: nil,
        action: nil
    )
    private let oneDriveButton = NSButton(
        radioButtonWithTitle: String(localized: "Sync with OneDrive"),
        target: nil,
        action: nil
    )
    private let primaryButton: NSButton
    private var quickUnlockButton: NSButton?
    private let onStorageModeChange: (PasswordVaultCreateStorageMode) -> Void
    private let onSubmit: (String, PasswordVaultCreateStorageMode) -> Void
    private let onQuickUnlock: () -> Void

    init(
        mode: Mode,
        storageMode: PasswordVaultCreateStorageMode,
        canQuickUnlock: Bool,
        isBusy: Bool,
        errorMessage: String?,
        onStorageModeChange: @escaping (PasswordVaultCreateStorageMode) -> Void,
        onSubmit: @escaping (String, PasswordVaultCreateStorageMode) -> Void,
        onQuickUnlock: @escaping () -> Void
    ) {
        self.mode = mode
        self.storageMode = storageMode
        self.onStorageModeChange = onStorageModeChange
        self.onSubmit = onSubmit
        self.onQuickUnlock = onQuickUnlock
        titleLabel = NSTextField(labelWithString: mode == .create
            ? String(localized: "Set Master Password") : String(localized: "Unlock Vault"))
        explanationLabel = NSTextField(labelWithString: mode == .create
            ? String(localized: "The master password encrypts your password vault. If forgotten, it cannot be recovered by any other means.")
            : String(localized: "Enter your master password to view and use saved passwords."))
        primaryButton = NSButton(title: isBusy
            ? (mode == .create ? String(localized: "Creating…") : String(localized: "Unlocking…"))
            : (mode == .create ? String(localized: "Create Vault") : String(localized: "Unlock Vault")),
            target: nil, action: nil)
        let height: CGFloat = mode == .create ? 354 : 216
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: height))

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        explanationLabel.font = .systemFont(ofSize: 11)
        explanationLabel.textColor = .secondaryLabelColor
        explanationLabel.maximumNumberOfLines = 2
        explanationLabel.lineBreakMode = .byWordWrapping
        addSubview(explanationLabel)

        if mode == .create {
            configureFieldLabel(storageLabel)
            addSubview(storageLabel)
            configureStorageButton(
                localOnlyButton,
                identifier: "passwordVaultStorageLocalOnly",
                action: #selector(storageModeClicked(_:))
            )
            configureStorageButton(
                oneDriveButton,
                identifier: "passwordVaultStorageOneDrive",
                action: #selector(storageModeClicked(_:))
            )
            localOnlyButton.tag = 0
            oneDriveButton.tag = 1
            addSubview(localOnlyButton)
            addSubview(oneDriveButton)
            updateStorageSelection()
        }

        configureFieldLabel(passwordLabel)
        addSubview(passwordLabel)
        configureSecureField(passwordField, identifier: "passwordVaultMasterPasswordField")
        addSubview(passwordField)
        configureVisibleField(visiblePasswordField)
        addSubview(visiblePasswordField)
        configureVisibilityButton(passwordVisibilityButton, action: #selector(togglePasswordVisibility(_:)))
        addSubview(passwordVisibilityButton)

        if mode == .create {
            configureFieldLabel(confirmationLabel)
            addSubview(confirmationLabel)
            configureSecureField(confirmationField, identifier: "passwordVaultConfirmPasswordField")
            addSubview(confirmationField)
            configureVisibleField(visibleConfirmationField)
            addSubview(visibleConfirmationField)
            configureVisibilityButton(confirmationVisibilityButton, action: #selector(toggleConfirmationVisibility(_:)))
            addSubview(confirmationVisibilityButton)
        }

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.stringValue = errorMessage ?? ""
        errorLabel.identifier = NSUserInterfaceItemIdentifier("passwordVaultAccessErrorLabel")
        addSubview(errorLabel)

        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked(_:))
        primaryButton.identifier = NSUserInterfaceItemIdentifier("passwordVaultAccessPrimaryButton")
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .large
        primaryButton.keyEquivalent = "\r"
        [passwordField, confirmationField, visiblePasswordField, visibleConfirmationField].forEach {
            $0.isEnabled = !isBusy
        }
        passwordVisibilityButton.isEnabled = !isBusy
        confirmationVisibilityButton.isEnabled = !isBusy
        localOnlyButton.isEnabled = !isBusy
        oneDriveButton.isEnabled = !isBusy
        primaryButton.isEnabled = false
        addSubview(primaryButton)

        if mode == .unlock && canQuickUnlock {
            let quick = NSButton(title: String(localized: "Use Quick Unlock"), target: self, action: #selector(quickUnlockClicked(_:)))
            quick.identifier = NSUserInterfaceItemIdentifier("passwordVaultQuickUnlockButton")
            quick.bezelStyle = .inline
            quick.isBordered = false
            quick.contentTintColor = .secondaryLabelColor
            quick.isEnabled = !isBusy
            quickUnlockButton = quick
            addSubview(quick)
        }
        updateSubmitState()
        layoutControls()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layoutControls()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, window?.firstResponder !== self.passwordField else { return }
            window?.makeFirstResponder(self.passwordField)
        }
    }

    private func layoutControls() {
        let inset: CGFloat = 12
        let availableWidth = max(0, bounds.width - inset * 2)
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 31, width: availableWidth, height: 20)
        explanationLabel.frame = NSRect(x: inset, y: bounds.height - 69, width: availableWidth, height: 34)
        let passwordLabelY: CGFloat
        let passwordFieldY: CGFloat
        if mode == .create {
            storageLabel.frame = NSRect(x: inset, y: bounds.height - 94, width: availableWidth, height: 16)
            let optionSpacing: CGFloat = 8
            let optionWidth = (availableWidth - optionSpacing) / 2
            localOnlyButton.frame = NSRect(x: inset, y: bounds.height - 150, width: optionWidth, height: 46)
            oneDriveButton.frame = NSRect(
                x: localOnlyButton.frame.maxX + optionSpacing,
                y: localOnlyButton.frame.minY,
                width: optionWidth,
                height: 54
            )
            passwordLabelY = bounds.height - 174
            passwordFieldY = bounds.height - 208
        } else {
            passwordLabelY = bounds.height - 96
            passwordFieldY = bounds.height - 130
        }
        passwordLabel.frame = NSRect(x: inset, y: passwordLabelY, width: availableWidth, height: 16)
        passwordField.frame = NSRect(x: inset, y: passwordFieldY, width: availableWidth, height: 30)
        visiblePasswordField.frame = passwordField.frame
        passwordVisibilityButton.frame = NSRect(x: passwordField.frame.maxX - 30, y: passwordField.frame.minY + 1, width: 28, height: 28)
        if mode == .create {
            confirmationLabel.frame = NSRect(x: inset, y: bounds.height - 233, width: availableWidth, height: 16)
            confirmationField.frame = NSRect(x: inset, y: bounds.height - 267, width: availableWidth, height: 30)
            visibleConfirmationField.frame = confirmationField.frame
            confirmationVisibilityButton.frame = NSRect(x: confirmationField.frame.maxX - 30, y: confirmationField.frame.minY + 1, width: 28, height: 28)
        }
        errorLabel.frame = NSRect(x: inset, y: 70, width: availableWidth, height: 15)
        primaryButton.frame = NSRect(x: inset, y: 34, width: availableWidth, height: 32)
        quickUnlockButton?.frame = NSRect(x: inset, y: 6, width: availableWidth, height: 24)
    }

    func submit() {
        let password = currentPassword
        guard !password.isEmpty else {
            errorLabel.stringValue = String(localized: "Enter a password.")
            return
        }
        if mode == .create, currentConfirmation != password {
            errorLabel.stringValue = String(localized: "The master passwords do not match.")
            return
        }
        onSubmit(password, storageMode)
    }

    func clearSecrets() {
        passwordField.stringValue = ""
        confirmationField.stringValue = ""
        visiblePasswordField.stringValue = ""
        visibleConfirmationField.stringValue = ""
    }

    private func configureFieldLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
    }

    private func configureSecureField(_ field: NSSecureTextField, identifier: String) {
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(primaryClicked(_:))
        field.delegate = self
    }

    private func configureVisibleField(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.isHidden = true
        field.delegate = self
    }

    private func configureVisibilityButton(_ button: NSButton, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        button.target = self
        button.action = action
        button.setAccessibilityLabel(String(localized: "Show Password"))
    }

    private func configureStorageButton(_ button: NSButton, identifier: String, action: Selector) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = action
        button.font = .systemFont(ofSize: 11.5, weight: .medium)
        button.alignment = .left
        button.wantsLayer = true
        button.layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        button.layer?.borderWidth = 1
        let help = button === localOnlyButton
            ? String(localized: "The encrypted vault stays on this Mac.")
            : String(localized: "Create the local vault first, then configure an encrypted OneDrive replica.")
        button.setAccessibilityHelp(help)
    }

    private func updateStorageSelection() {
        localOnlyButton.state = storageMode == .localOnly ? .on : .off
        oneDriveButton.state = storageMode == .oneDrive ? .on : .off
        localOnlyButton.layer?.backgroundColor = storageMode == .localOnly
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            : MainMenuVisualColors.controlSurface.cgColor
        oneDriveButton.layer?.backgroundColor = storageMode == .oneDrive
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            : MainMenuVisualColors.controlSurface.cgColor
        localOnlyButton.layer?.borderColor = storageMode == .localOnly
            ? NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
            : MainMenuVisualColors.controlBorder.cgColor
        oneDriveButton.layer?.borderColor = storageMode == .oneDrive
            ? NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
            : MainMenuVisualColors.controlBorder.cgColor
    }

    private var currentPassword: String { passwordField.isHidden ? visiblePasswordField.stringValue : passwordField.stringValue }
    private var currentConfirmation: String { confirmationField.isHidden ? visibleConfirmationField.stringValue : confirmationField.stringValue }

    func controlTextDidChange(_ obj: Notification) { updateSubmitState() }

    private func updateSubmitState() {
        primaryButton.isEnabled = !currentPassword.isEmpty && (mode == .unlock || currentPassword == currentConfirmation)
    }

    @objc private func togglePasswordVisibility(_ sender: NSButton) {
        visiblePasswordField.stringValue = currentPassword
        passwordField.stringValue = currentPassword
        passwordField.isHidden.toggle()
        visiblePasswordField.isHidden.toggle()
        sender.image = NSImage(systemSymbolName: passwordField.isHidden ? "eye.slash" : "eye", accessibilityDescription: nil)
        sender.setAccessibilityLabel(String(localized: passwordField.isHidden ? "Hide Password" : "Show Password"))
    }

    @objc private func toggleConfirmationVisibility(_ sender: NSButton) {
        visibleConfirmationField.stringValue = currentConfirmation
        confirmationField.stringValue = currentConfirmation
        confirmationField.isHidden.toggle()
        visibleConfirmationField.isHidden.toggle()
        sender.image = NSImage(systemSymbolName: confirmationField.isHidden ? "eye.slash" : "eye", accessibilityDescription: nil)
        sender.setAccessibilityLabel(String(localized: confirmationField.isHidden ? "Hide Password" : "Show Password"))
    }

    @objc private func primaryClicked(_ sender: Any?) { submit() }
    @objc private func quickUnlockClicked(_ sender: Any?) { onQuickUnlock() }
    @objc private func storageModeClicked(_ sender: NSButton) {
        storageMode = sender === oneDriveButton ? .oneDrive : .localOnly
        updateStorageSelection()
        onStorageModeChange(storageMode)
    }

#if DEBUG
    var secureFieldCountForTesting: Int { mode == .create ? 2 : 1 }
    var layoutForTesting: PasswordVaultAccessLayoutSnapshot {
        layoutSubtreeIfNeeded()
        let activeField = mode == .create ? confirmationField : passwordField
        let controls = [titleLabel, explanationLabel, passwordLabel, passwordField, errorLabel, primaryButton]
            + (mode == .create
                ? [storageLabel, localOnlyButton, oneDriveButton, confirmationLabel, confirmationField]
                : [])
        return PasswordVaultAccessLayoutSnapshot(
            title: titleLabel.stringValue,
            fieldLabel: passwordLabel.stringValue,
            explanation: explanationLabel.stringValue,
            titleFontSize: titleLabel.font?.pointSize ?? 0,
            verticalGapFromFieldToButton: activeField.frame.minY - primaryButton.frame.maxY,
            primaryButtonWidth: primaryButton.frame.width,
            controlsFitBounds: controls.allSatisfy { bounds.contains($0.frame) },
            explanationWrapsWithoutTruncation: explanationLabel.maximumNumberOfLines == 2
                && explanationLabel.lineBreakMode == .byWordWrapping
        )
    }

    func setValuesForTesting(password: String, confirmation: String?) {
        passwordField.stringValue = password
        confirmationField.stringValue = confirmation ?? ""
        visiblePasswordField.stringValue = password
        visibleConfirmationField.stringValue = confirmation ?? ""
        updateSubmitState()
    }

    var passwordIsVisibleForTesting: Bool { passwordField.isHidden }
    var passwordValueForTesting: String { currentPassword }
    var credentialControlsEnabledForTesting: Bool {
        [passwordField, confirmationField, visiblePasswordField, visibleConfirmationField].allSatisfy(\.isEnabled)
    }
    var primaryButtonEnabledForTesting: Bool { primaryButton.isEnabled }
    func togglePasswordVisibilityForTesting() { togglePasswordVisibility(passwordVisibilityButton) }

    var storageOptionTitlesForTesting: [String] {
        mode == .create ? [localOnlyButton.title, oneDriveButton.title] : []
    }

    var storageModeForTesting: PasswordVaultCreateStorageMode { storageMode }

    func selectStorageModeForTesting(_ storageMode: PasswordVaultCreateStorageMode) {
        self.storageMode = storageMode
        updateStorageSelection()
        onStorageModeChange(storageMode)
    }
#endif
}

private final class MainMenuCreateActionsView: NSView {
    private let indentationLevel: Int
    private let actionButton: MainMenuActionButton

    init(
        title: String,
        identifier: String,
        indentationLevel: Int,
        onAction: @escaping () -> Void
    ) {
        self.indentationLevel = indentationLevel
        actionButton = MainMenuActionButton(title: "", target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.rowHeight))
        actionButton.identifier = NSUserInterfaceItemIdentifier(identifier)
        actionButton.toolTip = title
        actionButton.setAccessibilityLabel(title)
        actionButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: title)
        actionButton.imagePosition = .imageOnly
        actionButton.isBordered = false
        actionButton.wantsLayer = true
        actionButton.layer?.cornerRadius = 9
        actionButton.layer?.backgroundColor = MainMenuVisualColors.controlSurface.cgColor
        actionButton.layer?.borderColor = MainMenuVisualColors.controlBorder.cgColor
        actionButton.layer?.borderWidth = 0.5
        actionButton.contentTintColor = .secondaryLabelColor
        actionButton.onAction = onAction
        actionButton.connectAction()
        addSubview(actionButton)
        layoutActionButton()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layoutActionButton()
    }

    private func layoutActionButton() {
        actionButton.frame = NSRect(
            x: MainMenuPanelRowView.leadingInset(for: indentationLevel),
            y: 3,
            width: 24,
            height: 24
        )
    }
}

// swiftlint:disable:next type_body_length
private final class MainMenuPanelRowView: NSControl, NSDraggingSource {
    private static let dragPasteboardType = NSPasteboard.PasteboardType("com.pastera.main-menu-row")
    struct ContextAction {
        let title: String
        let keyEquivalent: String
        let modifierFlags: NSEvent.ModifierFlags
        let action: () -> Void
    }
    struct QuickAction {
        let identifier: String
        let symbolName: String
        let title: String
        let shortcutText: String?
        let action: (() -> Void)?
    }
    enum RowKind {
        case snippetFolder
        case action
    }

    enum ShortcutPlacement {
        case trailingCommand
        case leadingItemNumber
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 8
        static let iconSize: CGFloat = 14
        static let iconSpacing: CGFloat = 7
        static let titleAccessorySpacing: CGFloat = 5
        static let accessoryChevronSpacing: CGFloat = 5
        static let chevronSize: CGFloat = 7
        static let accessoryButtonSize: CGFloat = 20
        static let indentationWidth: CGFloat = 14
    }

    fileprivate static func leadingInset(for indentationLevel: Int) -> CGFloat {
        Metrics.horizontalInset + CGFloat(indentationLevel) * Metrics.indentationWidth
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let itemNumberBadge = PasteraShortcutBadgeView(style: .itemNumber)
    private let shortcutButton = NSButton()
    private let quickActionStack = NSStackView()
    private var quickActionButtons = [MainMenuActionButton]()
    private let chevronView = NSImageView()
    private let editButton = NSButton()
    private let deleteButton = NSButton()
    private let showsChevron: Bool
    private let isExpanded: Bool
    private let rowKind: RowKind
    private let rowTitle: String
    private let deleteTitle: String
    private let indentationLevel: Int
    private let shortcutPlacement: ShortcutPlacement
    private let onHoverOpen: ((NSRect?) -> Void)?
    private let onEdit: (() -> Void)?
    private let showsEditButton: Bool
    private let onEditShortcut: (() -> Void)?
    private let onClearShortcut: (() -> Void)?
    private let onDelete: (() -> Void)?
    private let showsDeleteButton: Bool
    private let onDoubleClick: (() -> Void)?
    private let onConfirm: (NSRect?) -> Void
    private let contextActions: [ContextAction]
    private let quickActions: [QuickAction]
    private let dragIdentifier: String?
    private let onDragHover: (() -> Void)?
    private let onDrop: ((String, Bool) -> Bool)?
    private var trackingArea: NSTrackingArea?
    private var hoverOpenWorkItem: DispatchWorkItem?
    private var isMouseInside = false
    private var isKeyboardSelected = false
    private var didDragWindow = false
    private var pendingSingleClick: DispatchWorkItem?
    private var dragHoverWorkItem: DispatchWorkItem?
    var onHoverFocus: (() -> Void)?

    init(
        title: String,
        image: NSImage?,
        shortcutText: String? = nil,
        itemNumberText: String? = nil,
        rowKind: RowKind = .action,
        rowHeight: CGFloat = MainMenuPanelLayout.rowHeight,
        showsChevron: Bool = false,
        isExpanded: Bool = false,
        indentationLevel: Int = 0,
        contextActions: [ContextAction] = [],
        quickActions: [QuickAction] = [],
        shortcutPlacement: ShortcutPlacement = .trailingCommand,
        onHoverOpen: ((NSRect?) -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        showsEditButton: Bool = true,
        onEditShortcut: (() -> Void)? = nil,
        onClearShortcut: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        showsDeleteButton: Bool = true,
        onDoubleClick: (() -> Void)? = nil,
        dragIdentifier: String? = nil,
        onDragHover: (() -> Void)? = nil,
        onDrop: ((String, Bool) -> Bool)? = nil,
        deleteTitle: String? = nil,
        onConfirm: @escaping (NSRect?) -> Void
    ) {
        self.rowTitle = title
        self.rowKind = rowKind
        self.showsChevron = showsChevron
        self.isExpanded = isExpanded
        self.deleteTitle = deleteTitle ?? String(localized: "Delete")
        self.indentationLevel = indentationLevel
        self.contextActions = contextActions
        self.quickActions = quickActions
        self.shortcutPlacement = shortcutPlacement
        self.onHoverOpen = onHoverOpen
        self.onEdit = onEdit
        self.showsEditButton = showsEditButton
        self.onEditShortcut = onEditShortcut
        self.onClearShortcut = onClearShortcut
        self.onDelete = onDelete
        self.showsDeleteButton = showsDeleteButton
        self.onDoubleClick = onDoubleClick
        self.dragIdentifier = dragIdentifier
        self.onDragHover = onDragHover
        self.onDrop = onDrop
        self.onConfirm = onConfirm
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: rowHeight))
        if onDrop != nil {
            registerForDraggedTypes([Self.dragPasteboardType])
        }
        setup(
            title: title,
            image: image,
            shortcutText: shortcutText,
            itemNumberText: itemNumberText
        )
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        onHoverFocus?()
        updateAppearance()
        scheduleHoverOpenIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        cancelHoverOpen()
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        didDragWindow = true
        cancelHoverOpen()
        if let dragIdentifier {
            let item = NSPasteboardItem()
            item.setString(dragIdentifier, forType: Self.dragPasteboardType)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            draggingItem.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
            return
        }
        window?.performDrag(with: event)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation { .move }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dragPayload(from: sender) != nil else { return [] }
        scheduleDragHoverIfNeeded()
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragPayload(from: sender) == nil ? [] : .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        cancelDragHover()
        guard let payload = dragPayload(from: sender), let onDrop else { return false }
        let location = convert(sender.draggingLocation, from: nil)
        return onDrop(payload, location.y < bounds.midY)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        cancelDragHover()
    }

    private func scheduleDragHoverIfNeeded() {
        guard let onDragHover, dragHoverWorkItem == nil else { return }
        let workItem = DispatchWorkItem(block: onDragHover)
        dragHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + MainMenuPanelLayout.folderHoverOpenDelay, execute: workItem)
    }

    private func cancelDragHover() {
        dragHoverWorkItem?.cancel()
        dragHoverWorkItem = nil
    }

    private func dragPayload(from sender: NSDraggingInfo) -> String? {
        sender.draggingPasteboard.string(forType: Self.dragPasteboardType)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragWindow else {
            didDragWindow = false
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        if let onDoubleClick, titleLabel.frame.contains(location) {
            if event.clickCount >= 2 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
                onDoubleClick()
                return
            }
            let workItem = DispatchWorkItem { [weak self] in self?.onConfirm(self?.screenFrameForOpening) }
            pendingSingleClick = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
            return
        }
        if !shortcutButton.isHidden, shortcutButton.frame.contains(location) {
            editShortcut()
            return
        }
        if shortcutPlacement == .trailingCommand,
           !shortcutBadge.isHidden,
           shortcutBadge.frame.contains(location),
           onEditShortcut != nil {
            editShortcut()
            return
        }
        guard editButton.isHidden || !editButton.frame.contains(location) else { return }
        guard deleteButton.isHidden || !deleteButton.frame.contains(location) else { return }
        cancelHoverOpen()
        onConfirm(screenFrameForOpening)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeContextMenu()
    }

    private func makeContextMenu() -> NSMenu? {
        guard !contextActions.isEmpty || onEdit != nil || onEditShortcut != nil || onClearShortcut != nil || onDelete != nil else { return nil }
        let menu = NSMenu()
        for (index, action) in contextActions.enumerated() {
            let item = NSMenuItem(title: action.title, action: #selector(contextActionClicked(_:)), keyEquivalent: action.keyEquivalent)
            item.keyEquivalentModifierMask = action.modifierFlags
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        if !contextActions.isEmpty && (onEdit != nil || onEditShortcut != nil || onClearShortcut != nil || onDelete != nil) {
            menu.addItem(.separator())
        }
        let editItem = NSMenuItem(title: String(localized: "Edit"), action: #selector(editMenuItemClicked(_:)), keyEquivalent: "")
        if onEdit != nil {
            editItem.target = self
            menu.addItem(editItem)
        }
        if onEditShortcut != nil {
            let item = NSMenuItem(
                title: String(localized: "Edit Shortcut"),
                action: #selector(editShortcutMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if onClearShortcut != nil {
            let item = NSMenuItem(
                title: String(localized: "Clear Shortcut"),
                action: #selector(clearShortcutMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if onDelete != nil {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(deleteMenuItemClicked(_:)), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }
        return menu
    }

    @objc private func contextActionClicked(_ sender: NSMenuItem) {
        guard contextActions.indices.contains(sender.tag) else { return }
        contextActions[sender.tag].action()
    }

    func setKeyboardSelected(_ selected: Bool) {
        guard isKeyboardSelected != selected else { return }
        isKeyboardSelected = selected
        updateAppearance()
    }

    private func setup(
        title: String,
        image: NSImage?,
        shortcutText: String?,
        itemNumberText: String?
    ) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = image == nil
        imageView.contentTintColor = .secondaryLabelColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let resolvedItemNumberText = itemNumberText ?? (
            shortcutPlacement == .leadingItemNumber ? shortcutText : nil
        )
        shortcutBadge.shortcutText = shortcutPlacement == .leadingItemNumber ? nil : shortcutText
        shortcutBadge.style = .command
        itemNumberBadge.shortcutText = resolvedItemNumberText
        toolTip = mainMenuShortcutToolTip(title: title, includesPlainText: rowKind == .action,
                                          itemShortcut: resolvedItemNumberText)
        setAccessibilityHelp(toolTip)

        chevronView.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = .tertiaryLabelColor
        chevronView.isHidden = !showsChevron

        shortcutButton.identifier = NSUserInterfaceItemIdentifier("mainMenuRowShortcutButton")
        shortcutButton.setButtonType(.momentaryPushIn)
        shortcutButton.bezelStyle = .inline
        shortcutButton.isBordered = false
        shortcutButton.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        shortcutButton.imagePosition = .imageOnly
        shortcutButton.contentTintColor = .tertiaryLabelColor
        shortcutButton.toolTip = String(localized: "Edit Shortcut")
        shortcutButton.setAccessibilityLabel(String(localized: "Edit Shortcut"))
        shortcutButton.target = self
        shortcutButton.action = #selector(shortcutButtonClicked(_:))
        shortcutButton.isHidden = true

        quickActionStack.orientation = .horizontal
        quickActionStack.alignment = .centerY
        quickActionStack.spacing = 2
        quickActionStack.distribution = .fillEqually
        for quickAction in quickActions {
            let button = MainMenuActionButton(title: "", target: nil, action: nil)
            button.identifier = NSUserInterfaceItemIdentifier(quickAction.identifier)
            button.setButtonType(.momentaryPushIn)
            button.bezelStyle = .inline
            button.isBordered = false
            button.image = NSImage(systemSymbolName: quickAction.symbolName, accessibilityDescription: quickAction.title)
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            let help = [quickAction.title, quickAction.shortcutText].compactMap { $0 }.joined(separator: "  ")
            button.toolTip = help
            button.setAccessibilityLabel(quickAction.title)
            button.setAccessibilityHelp(help)
            button.onAction = { [weak self, weak button] in
                if let action = quickAction.action {
                    action()
                } else if let button {
                    self?.presentContextMenu(from: button)
                }
            }
            button.connectAction()
            button.isHidden = true
            quickActionStack.addArrangedSubview(button)
            quickActionButtons.append(button)
        }

        editButton.identifier = NSUserInterfaceItemIdentifier("mainMenuRowEditButton")
        editButton.setButtonType(.momentaryPushIn)
        editButton.bezelStyle = .inline
        editButton.isBordered = false
        editButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        editButton.imagePosition = .imageOnly
        editButton.contentTintColor = .tertiaryLabelColor
        editButton.toolTip = String(localized: "Edit")
        editButton.setAccessibilityLabel(String(localized: "Edit"))
        editButton.target = self
        editButton.action = #selector(editButtonClicked(_:))
        editButton.isHidden = true

        deleteButton.identifier = NSUserInterfaceItemIdentifier("mainMenuRowDeleteButton")
        deleteButton.setButtonType(.momentaryPushIn)
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .tertiaryLabelColor
        let deleteTooltip = "\(deleteTitle) (⌘D)"
        deleteButton.toolTip = deleteTooltip
        deleteButton.setAccessibilityLabel(deleteTooltip)
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked(_:))
        deleteButton.isHidden = true

        [
            imageView,
            titleLabel,
            shortcutBadge,
            itemNumberBadge,
            quickActionStack,
            shortcutButton,
            editButton,
            deleteButton,
            chevronView
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let leadingInset = Metrics.horizontalInset + CGFloat(indentationLevel) * Metrics.indentationWidth
        let shortcutButtonWidth: CGFloat = onEditShortcut == nil ? 0 : Metrics.accessoryButtonSize
        let shortcutButtonSpacing: CGFloat = onEditShortcut == nil ? 0 : Metrics.titleAccessorySpacing
        let hasVisibleEditButton = showsEditButton && onEdit != nil
        let shortcutEditSpacing: CGFloat = onEditShortcut == nil || !hasVisibleEditButton ? 0 : Metrics.titleAccessorySpacing
        let editButtonWidth: CGFloat = hasVisibleEditButton ? Metrics.accessoryButtonSize : 0
        let editButtonSpacing: CGFloat = !hasVisibleEditButton || onDelete == nil ? 0 : Metrics.titleAccessorySpacing
        let deleteButtonWidth: CGFloat = onDelete == nil || !showsDeleteButton ? 0 : Metrics.accessoryButtonSize
        let quickActionWidth = CGFloat(quickActions.count) * Metrics.accessoryButtonSize
            + CGFloat(max(0, quickActions.count - 1)) * quickActionStack.spacing
        let quickActionSpacing: CGFloat = quickActions.isEmpty ? 0 : Metrics.titleAccessorySpacing
        let trailingAccessoryAnchor = quickActions.isEmpty ? shortcutBadge.leadingAnchor : quickActionStack.leadingAnchor
        let hasItemNumber = resolvedItemNumberText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        var constraints = [
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: image == nil ? 0 : Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: image == nil ? 0 : Metrics.iconSize),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAccessoryAnchor,
                constant: -Metrics.titleAccessorySpacing
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutBadge.trailingAnchor.constraint(
                equalTo: shortcutButton.leadingAnchor,
                constant: -shortcutButtonSpacing
            ),

            itemNumberBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            itemNumberBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            quickActionStack.trailingAnchor.constraint(
                equalTo: shortcutButton.leadingAnchor,
                constant: -quickActionSpacing
            ),
            quickActionStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            quickActionStack.widthAnchor.constraint(equalToConstant: quickActionWidth),
            quickActionStack.heightAnchor.constraint(equalToConstant: Metrics.accessoryButtonSize),

            shortcutButton.trailingAnchor.constraint(
                equalTo: editButton.leadingAnchor,
                constant: -shortcutEditSpacing
            ),
            shortcutButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutButton.widthAnchor.constraint(equalToConstant: shortcutButtonWidth),
            shortcutButton.heightAnchor.constraint(equalToConstant: Metrics.accessoryButtonSize),

            editButton.trailingAnchor.constraint(
                equalTo: deleteButton.leadingAnchor,
                constant: -editButtonSpacing
            ),
            editButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: editButtonWidth),
            editButton.heightAnchor.constraint(equalToConstant: Metrics.accessoryButtonSize),

            deleteButton.trailingAnchor.constraint(
                equalTo: showsChevron ? chevronView.leadingAnchor : trailingAnchor,
                constant: showsChevron ? -Metrics.accessoryChevronSpacing : -Metrics.horizontalInset
            ),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: deleteButtonWidth),
            deleteButton.heightAnchor.constraint(equalToConstant: Metrics.accessoryButtonSize),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: showsChevron ? Metrics.chevronSize : 0),
            chevronView.heightAnchor.constraint(equalToConstant: showsChevron ? Metrics.chevronSize : 0)
        ]

        if hasItemNumber {
            if image == nil {
                constraints.append(imageView.leadingAnchor.constraint(equalTo: itemNumberBadge.trailingAnchor))
                constraints.append(titleLabel.leadingAnchor.constraint(
                    equalTo: itemNumberBadge.trailingAnchor,
                    constant: Metrics.titleAccessorySpacing
                ))
            } else {
                constraints.append(imageView.leadingAnchor.constraint(
                    equalTo: itemNumberBadge.trailingAnchor,
                    constant: Metrics.iconSpacing
                ))
                constraints.append(titleLabel.leadingAnchor.constraint(
                    equalTo: imageView.trailingAnchor,
                    constant: Metrics.iconSpacing
                ))
            }
        } else {
            constraints.append(imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset))
            constraints.append(titleLabel.leadingAnchor.constraint(
                equalTo: image == nil ? leadingAnchor : imageView.trailingAnchor,
                constant: image == nil ? leadingInset : Metrics.iconSpacing
            ))
        }

        NSLayoutConstraint.activate(constraints)

        updateAppearance()
    }

    fileprivate var screenFrameForOpening: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    private func scheduleHoverOpenIfNeeded() {
        guard let onHoverOpen else { return }
        cancelHoverOpen()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isMouseInside else { return }
            onHoverOpen(self.screenFrameForOpening)
        }
        hoverOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + MainMenuPanelLayout.folderHoverOpenDelay, execute: workItem)
    }

    private func cancelHoverOpen() {
        hoverOpenWorkItem?.cancel()
        hoverOpenWorkItem = nil
    }

    @objc private func editButtonClicked(_ sender: NSButton) {
        cancelHoverOpen()
        onEdit?()
    }

    @objc private func shortcutButtonClicked(_ sender: NSButton) {
        editShortcut()
    }

    @objc private func editMenuItemClicked(_ sender: NSMenuItem) {
        cancelHoverOpen()
        onEdit?()
    }

    @objc private func editShortcutMenuItemClicked(_ sender: NSMenuItem) {
        editShortcut()
    }

    @objc private func clearShortcutMenuItemClicked(_ sender: NSMenuItem) {
        clearShortcut()
    }

    @objc private func deleteButtonClicked(_ sender: NSButton) {
        delete()
    }

    @objc private func deleteMenuItemClicked(_ sender: NSMenuItem) {
        delete()
    }

    private func delete() {
        cancelHoverOpen()
        onDelete?()
    }

    private func editShortcut() {
        cancelHoverOpen()
        onEditShortcut?()
    }

    private func clearShortcut() {
        cancelHoverOpen()
        onClearShortcut?()
    }

    private func presentContextMenu(from button: NSButton) {
        guard let menu = makeContextMenu() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
    }

    private func updateAppearance() {
        let isEmphasized = isMouseInside || isKeyboardSelected
        layer?.backgroundColor = isEmphasized
            ? MainMenuVisualColors.hoveredRow.cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = .labelColor
        imageView.contentTintColor = isEmphasized ? .labelColor : .secondaryLabelColor
        shortcutBadge.setState(isEmphasized: isEmphasized)
        shortcutButton.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
        shortcutButton.isHidden = onEditShortcut == nil || !isEmphasized
        quickActionButtons.forEach {
            $0.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
            $0.isHidden = !isEmphasized
        }
        editButton.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
        editButton.isHidden = !showsEditButton || onEdit == nil || !isEmphasized
        deleteButton.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
        deleteButton.isHidden = onDelete == nil || !showsDeleteButton || !isEmphasized
        chevronView.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
    }

    #if DEBUG
    var contextMenuTitlesForTesting: [String] {
        makeContextMenu()?.items.compactMap { $0.isSeparatorItem ? nil : $0.title } ?? []
    }

    var buttonIdentifiersForTesting: [String] {
        ([shortcutButton, editButton, deleteButton] + quickActionButtons).compactMap { $0.identifier?.rawValue }
    }

    var visibleButtonIdentifiersForTesting: [String] {
        ([shortcutButton, editButton, deleteButton] + quickActionButtons)
            .filter { !$0.isHidden }
            .compactMap { $0.identifier?.rawValue }
    }
    #endif
}

#if DEBUG
extension MainMenuPanelController {
    func performMainMenuKeyEquivalentForTesting(_ event: NSEvent) -> Bool {
        panel?.performKeyEquivalent(with: event) ?? false
    }

    var mainMenuPanelContentSizeForTesting: NSSize {
        contentView.layoutSubtreeIfNeeded()
        return contentView.bounds.size
    }

    func mainMenuSnapshotPNGForTesting() throws -> Data {
        contentView.layoutSubtreeIfNeeded()
        guard let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            throw PasswordVaultError.saveFailed
        }
        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw PasswordVaultError.saveFailed
        }
        return data
    }

    var mainMenuOneDriveStatusButtonFramesForTesting: [NSRect] {
        contentView.layoutSubtreeIfNeeded()
        return mainMenuOneDriveStatusButtonsForTesting.map { button in
            button.superview?.convert(button.frame, to: contentView) ?? .zero
        }
    }

    var mainMenuToolbarButtonFramesForTesting: [String: NSRect] {
        contentView.layoutSubtreeIfNeeded()
        return Dictionary(uniqueKeysWithValues: collectButtons(in: contentView).compactMap { button in
            guard let identifier = button.identifier?.rawValue else { return nil }
            return (identifier, button.superview?.convert(button.frame, to: contentView) ?? .zero)
        })
    }

    func mainMenuToolbarToolTipForTesting(identifier: String) -> String? {
        (collectButtons(in: contentView).first {
            $0.identifier?.rawValue == identifier
        } as? MainMenuToolbarButton)?.hoverTip?.accessibilityLabel
    }

    var mainMenuHeaderToolTipsForTesting: [String: String] {
        contentView.subviews
            .compactMap { $0 as? MainMenuEmbeddedHeaderView }
            .first?
            .toolTipsForTesting ?? [:]
    }

    var mainMenuNonNavigatingHintTitlesForTesting: [String] {
        collectViews(in: contentView).compactMap { view in
            (view as? MainMenuEmbeddedEmptyRowView)?.titleForTesting
                ?? (view as? PasswordVaultQuickActionsCoachmarkView)?.titleForTesting
        }
    }

    func mainMenuRowToolTipForTesting(title: String) -> String? {
        if let toolTip = rowViewsForTesting.first(where: { $0.rowTitleForTesting == title })?.toolTip {
            return toolTip
        }
        return collectViews(in: contentView)
            .compactMap { $0 as? HistoryMenuRowView }
            .first { $0.textValuesForTesting.contains(title) }?
            .toolTip
    }

    var mainMenuEmbeddedSectionFramesForTesting: [String: NSRect]? {
        contentView.layoutSubtreeIfNeeded()
        let views = collectViews(in: contentView)
        let identifiers = [
            "header": "mainMenuHeaderBlock",
            "content": "mainMenuContentBlock",
            "footer": "mainMenuFooterDock"
        ]
        var frames = [String: NSRect]()
        for (key, identifier) in identifiers {
            guard let view = views.first(where: { $0.identifier?.rawValue == identifier }) else {
                return nil
            }
            frames[key] = view.superview?.convert(view.frame, to: contentView) ?? .zero
        }
        return frames
    }

    var mainMenuEmbeddedSeparatorCountForTesting: Int {
        contentView.layoutSubtreeIfNeeded()
        return collectViews(in: contentView)
            .filter { $0.identifier?.rawValue == "mainMenuSeparator" }
            .count
    }

    var mainMenuEmbeddedChromeForTesting: [String: MainMenuChromeStyle] {
        contentView.layoutSubtreeIfNeeded()
        let identifiers = [
            "header": "mainMenuHeaderBlock",
            "content": "mainMenuContentBlock",
            "footer": "mainMenuFooterDock"
        ]
        let views = collectViews(in: contentView)
        return Dictionary(uniqueKeysWithValues: identifiers.compactMap { key, identifier in
            guard let layer = views.first(where: { $0.identifier?.rawValue == identifier })?.layer else {
                return nil
            }
            let alpha = layer.backgroundColor.map { NSColor(cgColor: $0)?.alphaComponent ?? 0 } ?? 0
            return (key, MainMenuChromeStyle(backgroundAlpha: alpha, borderWidth: layer.borderWidth))
        })
    }

    var mainMenuSearchFieldFrameForTesting: NSRect? {
        contentView.layoutSubtreeIfNeeded()
        guard searchField.superview != nil else { return nil }
        return searchField.superview?.convert(searchField.frame, to: contentView) ?? .zero
    }

    var mainMenuFirstVisibleRowFrameForTesting: NSRect? {
        contentView.layoutSubtreeIfNeeded()
        return collectVisibleRowViews(in: contentView).first.map { row in
            row.superview?.convert(row.frame, to: contentView) ?? .zero
        }
    }

    var mainMenuSelectedRowFrameForTesting: NSRect? {
        contentView.layoutSubtreeIfNeeded()
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex),
              let view = keyboardEntries[selectedKeyboardEntryIndex].view() else {
            return nil
        }
        return view.superview?.convert(view.frame, to: contentView) ?? .zero
    }

    var mainMenuEmbeddedHeaderFramesForTesting: [String: NSRect]? {
        contentView.layoutSubtreeIfNeeded()
        guard let headerView = contentView.subviews.compactMap({ $0 as? MainMenuEmbeddedHeaderView }).first else {
            return nil
        }
        return headerView.framesForTesting.mapValues { headerView.convert($0, to: contentView) }
    }

    var mainMenuTypeFilterItemFramesForTesting: [NSRect] {
        contentView.subviews.compactMap { $0 as? MainMenuEmbeddedHeaderView }.first?.typeFilterItemFramesForTesting ?? []
    }

    var mainMenuSelectedTypeFilterTitlesForTesting: [String] {
        contentView.subviews.compactMap { $0 as? MainMenuEmbeddedHeaderView }.first?.selectedTypeFilterTitlesForTesting ?? []
    }

    var mainMenuEmbeddedHeaderCornerRadiiForTesting: [String: CGFloat]? {
        contentView.layoutSubtreeIfNeeded()
        guard let headerView = contentView.subviews.compactMap({ $0 as? MainMenuEmbeddedHeaderView }).first else {
            return nil
        }
        return headerView.cornerRadiiForTesting
    }

    var mainMenuButtonIdentifiersForTesting: [String] {
        contentView.layoutSubtreeIfNeeded()
        return collectButtons(in: contentView).compactMap { $0.identifier?.rawValue }
    }

    var mainMenuButtonTitlesForTesting: [String] {
        contentView.layoutSubtreeIfNeeded()
        return collectButtons(in: contentView).map(\.title).filter { !$0.isEmpty }
    }

    var mainMenuButtonImageNamesForTesting: [String: String] {
        contentView.layoutSubtreeIfNeeded()
        return Dictionary(uniqueKeysWithValues: collectButtons(in: contentView).compactMap { button in
            guard let identifier = button.identifier?.rawValue,
                  let imageName = button.image?.name() else { return nil }
            return (identifier, imageName)
        })
    }

    func mainMenuButtonFrameForTesting(identifier: String) -> NSRect? {
        contentView.layoutSubtreeIfNeeded()
        guard let button = collectButtons(in: contentView).first(where: {
            $0.identifier?.rawValue == identifier
        }) else { return nil }
        return button.superview?.convert(button.frame, to: contentView)
    }

    func performMainMenuButtonClickForTesting(identifier: String) {
        collectButtons(in: contentView).first(where: {
            $0.identifier?.rawValue == identifier
        })?.performClick(nil)
    }

    func mainMenuActionRowFrameForTesting(title: String) -> NSRect? {
        rowViewsForTesting
            .first { $0.rowKindForTesting == .action && $0.rowTitleForTesting == title }
            .map { $0.superview?.convert($0.frame, to: contentView) ?? .zero }
    }

    func mainMenuSnippetRowFrameForTesting(title: String) -> NSRect? {
        rowViewsForTesting
            .first { $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title }
            .map { $0.superview?.convert($0.frame, to: contentView) ?? .zero }
    }

    func mainMenuSnippetTitleFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleFrameForTesting
    }

    func mainMenuActionTitleFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .action && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleFrameForTesting
    }

    func mainMenuRowShortcutFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: { $0.rowTitleForTesting == title }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.shortcutFrameForTesting
    }

    func mainMenuRowShortcutTextForTesting(title: String) -> String? {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .shortcutTextForTesting
    }

    func mainMenuRowItemNumberFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: { $0.rowTitleForTesting == title }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.itemNumberFrameForTesting
    }

    func mainMenuRowItemNumberTextForTesting(title: String) -> String? {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .itemNumberTextForTesting
    }

    func mainMenuSnippetTitleAvailableWidthForTesting(title: String) -> CGFloat? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleAvailableWidthForTesting
    }

    func mainMenuActionTitleAvailableWidthForTesting(title: String) -> CGFloat? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .action && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleAvailableWidthForTesting
    }

    func mainMenuRowContextMenuTitlesForTesting(title: String) -> [String] {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .contextMenuTitlesForTesting ?? []
    }

    func mainMenuRowButtonIdentifiersForTesting(title: String) -> [String] {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .buttonIdentifiersForTesting ?? []
    }

    func mainMenuRowVisibleButtonIdentifiersForTesting(title: String) -> [String] {
        rowViewsForTesting
            .first { $0.rowTitleForTesting == title }?
            .visibleButtonIdentifiersForTesting ?? []
    }

    func mainMenuRenderedRowCountForTesting(title: String) -> Int {
        rowViewsForTesting.filter { $0.rowTitleForTesting == title }.count
    }

    func mainMenuRowHasImageForTesting(title: String) -> Bool {
        rowViewsForTesting.first { $0.rowTitleForTesting == title }?.hasImageForTesting ?? false
    }

    func mainMenuRowImageFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: { $0.rowTitleForTesting == title }) else { return nil }
        row.layoutSubtreeIfNeeded()
        return row.convert(row.imageFrameForTesting, to: contentView)
    }

    func performMainMenuRowDoubleClickForTesting(title: String) {
        rowViewsForTesting.first { $0.rowTitleForTesting == title }?.performDoubleClickForTesting()
    }

    func performMainMenuRowDeleteForTesting(title: String) {
        rowViewsForTesting.first { $0.rowTitleForTesting == title }?.performDeleteForTesting()
    }

    var mainMenuPasswordEditorIsVisibleForTesting: Bool { passwordVaultEditorState != nil }
    var passwordVaultFolderEditorIsVisibleForTesting: Bool { passwordVaultFolderEditorState != nil }

    func beginCreatingPasswordVaultFolderForTesting() {
        beginCreatingPasswordVaultFolder()
    }

    func discardPasswordVaultFolderEditorForTesting() {
        passwordVaultFolderEditorState = nil
        reloadContentKeepingTopLeft()
    }

    var passwordVaultAccessSecureFieldCountForTesting: Int {
        (passwordVaultAccessView?.secureFieldCountForTesting ?? 0)
            + (passwordVaultRemoteCredentialsView == nil ? 0 : 1)
    }

    var passwordVaultAccessLayoutForTesting: PasswordVaultAccessLayoutSnapshot? {
        passwordVaultAccessView?.layoutForTesting
    }

    var vaultCreateStorageTitlesForTesting: [String] {
        passwordVaultAccessView?.storageOptionTitlesForTesting ?? []
    }

    var vaultCreateStorageSelectionForTesting: String {
        passwordVaultAccessView?.storageModeForTesting.rawValue
            ?? passwordVaultCreateStorageMode.rawValue
    }

    func selectPasswordVaultCreateStorageForTesting(_ rawValue: String) {
        guard let storageMode = PasswordVaultCreateStorageMode(rawValue: rawValue) else { return }
        passwordVaultAccessView?.selectStorageModeForTesting(storageMode)
    }

    var passwordVaultPageForTesting: String {
        switch passwordVaultPage {
        case .vault: "vault"
        case .remoteCredentials: "remoteCredentials"
        case .conflictSummary: "conflictSummary"
        case .localCopyRecovery: "localCopyRecovery"
        }
    }

    var vaultInlinePageTextsForTesting: [String] {
        if let passwordVaultRemoteCredentialsView {
            return passwordVaultRemoteCredentialsView.textValuesForTesting
        }
        return passwordVaultInlineActionView?.textValuesForTesting ?? []
    }

    var passwordVaultSearchQueryForTesting: String { passwordVaultSearchQuery }

    var vaultRemoteCredentialValueForTesting: String? {
        passwordVaultRemoteCredentialsView?.secretValueForTesting
    }

    var vaultInlineActionsFitViewportForTesting: Bool {
        let actionPrefixes = [
            "passwordVaultRecovery",
            "passwordVaultRemoteCredential",
            "passwordVaultConflict"
        ]
        return collectButtons(in: contentView).filter { button in
            guard let identifier = button.identifier?.rawValue else { return false }
            return actionPrefixes.contains { identifier.hasPrefix($0) }
        }.allSatisfy { button in
            guard let superview = button.superview else { return false }
            let frame = superview.convert(button.frame, to: contentView)
            return frame.minY >= contentBlockFrame.minY - 0.5
                && frame.maxY <= contentBlockFrame.maxY + 0.5
        }
    }

    func setPasswordVaultRemoteCredentialForTesting(_ value: String) {
        passwordVaultRemoteCredentialsView?.setSecretForTesting(value)
    }

    func submitPasswordVaultRemoteCredentialForTesting() {
        passwordVaultRemoteCredentialsView?.submit()
    }

    func performPasswordVaultContextBackForTesting() {
        returnFromPasswordVaultContextPage()
    }

    var passwordVaultControlsFitVisibleContentForTesting: Bool {
        contentView.layoutSubtreeIfNeeded()
        let identifiers = Set([
            "passwordVaultAccessPrimaryButton",
            "passwordVaultMasterPasswordField",
            "passwordVaultConfirmPasswordField",
            "mainMenuContentCreatePasswordFolderButton",
            "mainMenuContentCreatePasswordButton",
        ])
        return collectViews(in: contentView).filter {
            guard let identifier = $0.identifier?.rawValue else { return false }
            return identifiers.contains(identifier)
        }.allSatisfy { view in
            guard let superview = view.superview else { return false }
            return view.frame.minX >= -0.5 && view.frame.maxX <= superview.bounds.maxX + 0.5
        }
    }

    func setPasswordVaultAccessValuesForTesting(password: String, confirmation: String? = nil) {
        passwordVaultAccessView?.setValuesForTesting(password: password, confirmation: confirmation)
    }

    var passwordVaultAccessPasswordIsVisibleForTesting: Bool {
        passwordVaultAccessView?.passwordIsVisibleForTesting ?? false
    }

    var passwordVaultAccessPasswordValueForTesting: String? {
        passwordVaultAccessView?.passwordValueForTesting
    }

    var passwordVaultAccessCredentialControlsEnabledForTesting: Bool {
        passwordVaultAccessView?.credentialControlsEnabledForTesting ?? false
    }

    var passwordVaultAccessPrimaryButtonEnabledForTesting: Bool {
        passwordVaultAccessView?.primaryButtonEnabledForTesting ?? false
    }

    func togglePasswordVaultAccessPasswordVisibilityForTesting() {
        passwordVaultAccessView?.togglePasswordVisibilityForTesting()
    }

    func submitPasswordVaultAccessForTesting() {
        passwordVaultAccessView?.submit()
    }

    @discardableResult
    func submitPasswordVaultAccessUsingReturnForTesting(password: String, confirmation: String? = nil) -> Bool {
        guard let panel, let passwordVaultAccessView else { return false }
        passwordVaultAccessView.setValuesForTesting(password: password, confirmation: confirmation)
        let fields = collectViews(in: passwordVaultAccessView).compactMap { $0 as? NSSecureTextField }
        let targetField = confirmation == nil ? fields.first : fields.last
        guard let targetField,
              panel.makeFirstResponder(targetField),
              let fieldEditor = panel.fieldEditor(true, for: targetField) as? NSTextView else { return false }
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        return true
    }

    @discardableResult
    func submitVisiblePasswordVaultReturnFieldForTesting(_ value: String) -> Bool {
        guard let panel else { return false }
        let views = collectViews(in: contentView)
        let field: NSTextField
        if let textField = views.compactMap({ $0 as? PasswordVaultReturnTextField }).first(where: { !$0.isHidden }) {
            field = textField
        } else if let secureField = views.compactMap({ $0 as? PasswordVaultReturnSecureField }).first(where: { !$0.isHidden }) {
            field = secureField
        } else {
            return false
        }
        field.stringValue = value
        guard panel.makeFirstResponder(field),
              let fieldEditor = panel.fieldEditor(true, for: field) as? NSTextView else { return false }
        fieldEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        return true
    }

    func performMainMenuRowConfirmForTesting(title: String) {
        keyboardEntries.first(where: { $0.title == title })?.confirm()
    }

    var passwordVaultEditorStepForTesting: String? {
        switch passwordVaultEditorState {
        case let .create(_, step, _), let .edit(_, _, step, _): return step.rawValue
        case nil: return nil
        }
    }

    var passwordVaultEditorHeightForTesting: CGFloat? { passwordVaultStepEditorView?.frame.height }

    func beginCreatingPasswordVaultEntryForTesting(in folderID: PasswordVaultFolder.ID) {
        beginCreatingPasswordVaultEntry(in: folderID)
    }

    func updatePasswordVaultStepValueForTesting(_ value: String) {
        passwordVaultStepEditorView?.value = value
    }

    func commitPasswordVaultStepForTesting() {
        passwordVaultStepEditorView?.commit()
    }

    var mainMenuOneDriveStatusTintColorForTesting: NSColor? {
        mainMenuOneDriveStatusButtonsForTesting.first?.contentTintColor
    }

    var mainMenuOneDriveStatusToolTipForTesting: String? {
        (mainMenuOneDriveStatusButtonsForTesting.first as? MainMenuOneDriveStatusButton)?.hoverTip?.title
    }

    func performMainMenuOneDriveStatusClickForTesting() {
        mainMenuOneDriveStatusButtonsForTesting.first?.performClick(nil)
    }

    func performMainMenuSearchClickForTesting() {
        collectButtons(identifier: "mainMenuSearchButton").first?.performClick(nil)
    }

    func updateMainMenuSearchQueryForTesting(_ query: String) {
        updateSearchQuery(query)
    }

    func flushPendingMainMenuSearchQueryForTesting() {
        emitSearchQueryChangeIfReady()
    }

    var selectedMainMenuTitleForTesting: String? {
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else { return nil }
        return keyboardEntries[selectedKeyboardEntryIndex].title
    }

    var mainMenuVisibleRowTitlesForTesting: [String] {
        visibleMainMenuRowTitles
    }

    var mainMenuSelectedModeForTesting: String {
        switch selectedMode {
        case .history:
            return "history"
        case .snippets:
            return "snippets"
        case .passwordVault:
            return "passwordVault"
        }
    }

    var mainMenuSnippetFolderTitleForTesting: String? {
        currentSnippetFolderTitle
    }

    var mainMenuExpandedSnippetFolderIDForTesting: SnippetFolder.ID? {
        expandedSnippetFolderID
    }

    var mainMenuEditorTitleForTesting: String? {
        switch inlineEditorState {
        case let .snippetFolder(_, _, draftTitle, _):
            return draftTitle
        case let .snippet(_, _, _, draftTitle, _, _):
            return draftTitle
        case let .newSnippetFolder(draftTitle, _), let .newSnippet(_, draftTitle, _, _):
            return draftTitle
        case .history, nil:
            return nil
        }
    }

    var mainMenuEditorContentForTesting: String? {
        switch inlineEditorState {
        case let .history(_, _, draftText, _):
            return draftText
        case let .snippet(_, _, _, _, draftContent, _):
            return draftContent
        case let .newSnippet(_, _, draftContent, _):
            return draftContent
        case .snippetFolder, .newSnippetFolder, nil:
            return nil
        }
    }

    var mainMenuEditorErrorForTesting: String? {
        switch inlineEditorState {
        case let .history(_, _, _, error),
             let .snippetFolder(_, _, _, error),
             let .snippet(_, _, _, _, _, error),
             let .newSnippetFolder(_, error),
             let .newSnippet(_, _, _, error):
            return error
        case nil:
            return nil
        }
    }

    var mainMenuEditorButtonTitlesForTesting: [String] {
        inlineEditorView?.buttonTitlesForTesting ?? []
    }

    var isMainMenuSearchFieldVisibleForTesting: Bool {
        isSearchVisible
    }

    var isMainMenuSearchFieldFocusedForTesting: Bool {
        panel?.firstResponder === searchField || searchField.currentEditor() != nil
    }

    var contentBackgroundAlphaForTesting: CGFloat {
        CGFloat(contentView.layer?.backgroundColor?.alpha ?? 0)
    }

    var contentBackgroundLuminanceForTesting: CGFloat {
        guard let cgColor = contentView.layer?.backgroundColor,
              let components = cgColor.components else {
            return 1
        }
        let red = components.count >= 3 ? components[0] : components[0]
        let green = components.count >= 3 ? components[1] : components[0]
        let blue = components.count >= 3 ? components[2] : components[0]
        return red * 0.2126 + green * 0.7152 + blue * 0.0722
    }

    func selectMainMenuItemForTesting(title: String) {
        guard let index = keyboardEntries.firstIndex(where: { $0.title == title }) else { return }
        selectKeyboardEntry(at: index, triggerChildPanel: false)
    }

    func beginEditingHistoryForTesting(id: PasteboardHistory.ID) {
        beginEditingHistory(id)
    }

    func beginEditingSnippetFolderForTesting(id: SnippetFolder.ID) {
        beginEditingSnippetFolder(id)
    }

    func beginEditingSnippetForTesting(id: Snippet.ID) {
        beginEditingSnippet(id)
    }

    func beginCreatingSnippetForTesting() { beginCreatingSnippet() }
    func beginCreatingSnippetFolderForTesting() { beginCreatingSnippetFolder() }
    func toggleWorkspaceEditingForTesting() { toggleWorkspaceEditing() }

    func beginEditingSnippetFolderShortcutForTesting(id: SnippetFolder.ID) {
        beginEditingFolderShortcut(id)
    }

    var isMainMenuFolderShortcutEditorVisibleForTesting: Bool {
        folderShortcutEditorView?.superview != nil
    }

    func recordMainMenuFolderShortcutForTesting(_ keyCombo: KeyCombo) {
        folderShortcutEditorView?.recordKeyComboForTesting(keyCombo)
    }

    func clearMainMenuFolderShortcutForTesting() {
        folderShortcutEditorView?.clearForTesting()
    }

    func updateMainMenuEditorDraftForTesting(title: String? = nil, content: String? = nil) {
        inlineEditorView?.updateDraft(title: title, content: content)
        switch inlineEditorState {
        case let .history(id, originalText, draftText, error):
            inlineEditorState = .history(
                id,
                originalText: originalText,
                draftText: content ?? draftText,
                error: error
            )
        case let .snippetFolder(id, originalTitle, draftTitle, error):
            inlineEditorState = .snippetFolder(
                id,
                originalTitle: originalTitle,
                draftTitle: title ?? draftTitle,
                error: error
            )
        case let .snippet(id, originalTitle, originalContent, draftTitle, draftContent, error):
            inlineEditorState = .snippet(
                id,
                originalTitle: originalTitle,
                originalContent: originalContent,
                draftTitle: title ?? draftTitle,
                draftContent: content ?? draftContent,
                error: error
            )
        case let .newSnippetFolder(draftTitle, error):
            inlineEditorState = .newSnippetFolder(draftTitle: title ?? draftTitle, error: error)
        case let .newSnippet(folderID, draftTitle, draftContent, error):
            inlineEditorState = .newSnippet(
                folderID, draftTitle: title ?? draftTitle, draftContent: content ?? draftContent, error: error
            )
        case nil:
            break
        }
    }

    @discardableResult
    func commitMainMenuEditorForTesting() -> Bool {
        commitInlineEditorFromCurrentDraft()
    }

    func discardMainMenuEditorForTesting() {
        discardInlineEditor()
    }

    func setMainMenuDeleteConfirmationRunnerForTesting(
        _ runner: @escaping (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult
    ) {
        deleteConfirmationRunner = runner
    }

    func handleMainMenuNavigationForTesting(_ event: NSEvent) -> Bool {
        handleKeyboardNavigation(event)
    }

    private var rowViewsForTesting: [MainMenuPanelRowView] {
        contentView.layoutSubtreeIfNeeded()
        return collectRowViews(in: contentView)
    }

    private var mainMenuOneDriveStatusButtonsForTesting: [NSButton] {
        collectButtons(identifier: "mainMenuOneDriveStatusButton")
    }

    private func collectButtons(identifier: String) -> [NSButton] {
        collectButtons(in: contentView)
            .filter { $0.identifier?.rawValue == identifier && !$0.isHidden }
    }

    private func collectButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        for subview in view.subviews {
            buttons.append(contentsOf: collectButtons(in: subview))
        }
        return buttons
    }

    private func collectViews(in view: NSView) -> [NSView] {
        var views = view.subviews
        for subview in view.subviews {
            views.append(contentsOf: collectViews(in: subview))
        }
        return views
    }

    private func collectRowViews(in view: NSView) -> [MainMenuPanelRowView] {
        var rows = view.subviews.compactMap { $0 as? MainMenuPanelRowView }
        for subview in view.subviews {
            rows.append(contentsOf: collectRowViews(in: subview))
        }
        return rows
    }

    private func collectVisibleRowViews(in view: NSView) -> [NSView] {
        var rows = view.subviews.filter {
            $0 is HistoryMenuRowView ||
                $0 is MainMenuPanelRowView ||
                $0 is MainMenuEmbeddedEmptyRowView
        }
        for subview in view.subviews {
            rows.append(contentsOf: collectVisibleRowViews(in: subview))
        }
        return rows
    }
}

private extension MainMenuEmbeddedHeaderView {
    var framesForTesting: [String: NSRect] {
        var frames = [
            "title": titleLabel.frame
        ]
        if let first = typeButtons.first, let last = typeButtons.last {
            frames["typeFilter"] = first.frame.union(last.frame)
        }
        if previousButton.superview != nil {
            frames["previous"] = previousButton.frame
        }
        if subtitleLabel.superview != nil {
            frames["page"] = subtitleLabel.frame
            let textFrame = subtitleLabel.cell?.drawingRect(forBounds: subtitleLabel.bounds) ?? subtitleLabel.bounds
            frames["pageText"] = subtitleLabel.convert(textFrame, to: self)
        }
        if nextButton.superview != nil {
            frames["next"] = nextButton.frame
        }
        if backButton.superview != nil && !backButton.isHidden {
            frames["back"] = backButton.frame
        }
        return frames
    }

    var cornerRadiiForTesting: [String: CGFloat] {
        [
            "typeFilter": typeButtons.first?.layer?.cornerRadius ?? 0,
            "previous": previousButton.layer?.cornerRadius ?? 0,
            "next": nextButton.layer?.cornerRadius ?? 0
        ]
    }

    var toolTipsForTesting: [String: String] {
        [
            "typeFilter": typeButtons.first(where: \.isCurrent)?.toolTip,
            "previous": previousButton.toolTip,
            "next": nextButton.toolTip
        ].compactMapValues { $0 }
    }
}

private extension MainMenuPanelRowView {
    var rowTitleForTesting: String {
        rowTitle
    }

    var rowKindForTesting: RowKind {
        rowKind
    }

    var titleFrameForTesting: NSRect {
        titleLabel.frame
    }

    var shortcutFrameForTesting: NSRect {
        shortcutBadge.frame
    }

    var shortcutTextForTesting: String? {
        shortcutBadge.shortcutText
    }

    var itemNumberFrameForTesting: NSRect {
        itemNumberBadge.frame
    }

    var itemNumberTextForTesting: String? {
        itemNumberBadge.shortcutText
    }

    var hasImageForTesting: Bool { imageView.image != nil && imageView.superview != nil }
    var imageFrameForTesting: NSRect { imageView.frame }

    func performDoubleClickForTesting() { onDoubleClick?() }
    func performDeleteForTesting() { onDelete?() }

    var titleAvailableWidthForTesting: CGFloat {
        let trailingLimit: CGFloat
        if quickActionButtons.contains(where: { !$0.isHidden }) {
            trailingLimit = quickActionStack.frame.minX - Metrics.titleAccessorySpacing
        } else if shortcutPlacement == .trailingCommand, !shortcutBadge.isHidden {
            trailingLimit = shortcutBadge.frame.minX - Metrics.titleAccessorySpacing
        } else if !shortcutButton.isHidden {
            trailingLimit = shortcutButton.frame.minX - Metrics.titleAccessorySpacing
        } else if !editButton.isHidden {
            trailingLimit = editButton.frame.minX - Metrics.titleAccessorySpacing
        } else if !deleteButton.isHidden {
            trailingLimit = deleteButton.frame.minX - Metrics.titleAccessorySpacing
        } else if !chevronView.isHidden {
            trailingLimit = chevronView.frame.minX - Metrics.titleAccessorySpacing
        } else {
            trailingLimit = bounds.maxX - Metrics.horizontalInset
        }
        return max(0, trailingLimit - titleLabel.frame.minX)
    }
}
#endif
