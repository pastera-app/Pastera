//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Carbon
import Combine
import Dependencies
import Magnet
import RxCocoa
import RxSwift

// swiftlint:disable file_length

private final class HistoryBrowserMenu: NSMenu {
    weak var headerView: HistoryMenuHeaderView?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if headerView?.handleMenuTrackingKeyDown(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct HistoryItemPresentation {
    let title: String
    let image: NSImage?
    let toolTip: String?
    let previewText: String?
}

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    fileprivate var snippetMenu: NSMenu?
    // StatusMenu
    var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = NSImage(resource: .iconFolder)
    fileprivate let snippetIcon = NSImage(resource: .iconText)
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    fileprivate var historyMenuState = HistoryMenuPaginationState()
    var historyPanelController: HistoryBrowserPanelController?
    var snippetPanelController: SnippetBrowserPanelController?
    var mainMenuPanelController: MainMenuPanelController?
    private let passwordVaultUIControllerProvider: () -> PasswordVaultUIController = {
        AppEnvironment.current.passwordVaultUIController
    }
    private let passwordVaultSyncServiceProvider: () -> PasswordVaultSyncControlling = {
        AppEnvironment.current.passwordVaultSyncService
    }
    private weak var installedPasswordVaultUIController: PasswordVaultUIController?
    private var installedPasswordVaultSyncService: PasswordVaultSyncControlling?
    private var passwordVaultSyncObserver: UUID?
    private(set) var passwordVaultSyncSnapshot: PasswordVaultSyncSnapshot?
    var passwordVaultUIController: PasswordVaultUIController {
        let controller = passwordVaultUIControllerProvider()
        if installedPasswordVaultUIController !== controller {
            installedPasswordVaultUIController?.onChange = nil
            installedPasswordVaultUIController = controller
            controller.onChange = { [weak self] in
                self?.mainMenuPanelController?.reloadContentIfVisible()
            }
        }
        installPasswordVaultSyncObservationIfNeeded()
        return controller
    }
    var passwordVaultSyncService: PasswordVaultSyncControlling {
        installPasswordVaultSyncObservationIfNeeded()
        return passwordVaultSyncServiceProvider()
    }
    private lazy var historyEditorWindowController = HistoryEditorWindowController(
        repository: pasteboardHistoryRepository,
        ocrIndexer: pasteboardHistoryOCRIndexer,
        scriptCoordinator: AppEnvironment.current.clipboardScriptCoordinator,
        promptOptimizationService: AppEnvironment.current.promptOptimizationService,
        onSaved: { [weak self] in
            self?.refreshHistorySurfacesIfVisible()
            if let menu = self?.historyMenu {
                self?.configureHistoryBrowserMenu(menu)
            }
        }
    )
    var panelDismissLocalMonitor: Any?
    var panelDismissGlobalMonitor: Any?
    var secureEventInputStatusTimer: Timer?
    var oneDriveStatusObservation: OneDriveProcessStatusObservation?
    var secureEventInputEnabledProvider: () -> Bool = {
        IsSecureEventInputEnabled()
    }
    static let panelDismissMouseEventMask: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    private enum SelectionActionMetrics {
        static let delay: TimeInterval = 0.05
    }

    var selectionActionScheduler: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository
    @Dependency(\.pasteboardHistoryOCRIndexer)
    private var pasteboardHistoryOCRIndexer
    @Dependency(\.snippetRepository)
    private var snippetRepository
    @Dependency(\.mainQueue)
    private var mainQueue
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
    }

    deinit {
        if let passwordVaultSyncObserver {
            installedPasswordVaultSyncService?.removeObserver(passwordVaultSyncObserver)
        }
        secureEventInputStatusTimer?.invalidate()
        oneDriveStatusObservation?.cancel()
        removePanelDismissMonitors()
        removeStatusItem()
    }

    func setup() {
        installPasswordVaultSyncObservationIfNeeded()
        createClipMenu()
        configureStatusItemFromDefaults()
        startSecureEventInputStatusMonitoring()
        startOneDriveStatusMonitoring()
        bind()
    }

}

private extension MenuManager {
    func installPasswordVaultSyncObservationIfNeeded() {
        let service = passwordVaultSyncServiceProvider()
        guard installedPasswordVaultSyncService !== service else { return }
        if let passwordVaultSyncObserver {
            installedPasswordVaultSyncService?.removeObserver(passwordVaultSyncObserver)
        }
        installedPasswordVaultSyncService = service
        passwordVaultSyncSnapshot = service.snapshot
        passwordVaultSyncObserver = service.addObserver { [weak self, weak service] snapshot in
            guard let self, self.installedPasswordVaultSyncService === service else { return }
            self.passwordVaultSyncSnapshot = snapshot
            let refresh: () -> Void = { [weak self] in
                guard let self else { return }
                self.mainMenuPanelController?.refreshPasswordVaultSyncPresentationIfVisible(
                    snapshot: snapshot
                )
            }
            if Thread.isMainThread {
                refresh()
            } else {
                DispatchQueue.main.async(execute: refresh)
            }
        }
    }
}

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType, triggerKeyCombo: KeyCombo? = nil) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        switch type {
        case .main, .history:
            panelController.openHistoryFromMainMenu()
        case .snippet:
            panelController.openSnippetsFromMainMenu()
        case .passwordVault:
            panelController.openPasswordVaultFromMainMenu()
        }
        panelController.show(at: NSEvent.mouseLocation, pinned: false)
        installPanelDismissMonitorsIfNeeded()
    }

    func popUpSnippetFolder(_ folderDetail: SnippetFolderDetail, triggerKeyCombo: KeyCombo? = nil) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        panelController.openSnippetFolderFromMainMenu(folderDetail.folder.id)
        panelController.show(at: NSEvent.mouseLocation, pinned: false)
        installPanelDismissMonitorsIfNeeded()
    }
}

// MARK: - Binding
extension MenuManager {
    func bind() {
        pasteboardHistoryRepository.observeHistoryChanges()
            .receive(on: mainQueue)
            .sink { [weak self] _ in self?.refreshHistorySurfacesIfVisible() }
            .store(in: &cancellables)
        snippetRepository.observeFolders()
            .receive(on: mainQueue)
            .sink { [weak self] _ in self?.refreshSnippetSurfacesIfVisible() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(
            for: CPYWindowAppearance.opacityDidChangeNotification,
            object: AppEnvironment.current.defaults
        )
        .receive(on: mainQueue)
        .sink { [weak self] _ in self?.refreshVisiblePanelBackgrounds() }
        .store(in: &cancellables)
        // Menu icon
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.showStatusItem, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            })
            .disposed(by: disposeBag)
        // Sort clips
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.reorderClipsAfterPasting, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                guard let wSelf = self else { return }
                wSelf.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings
        let defaults = AppEnvironment.current.defaults
        var menuChangedObservables = [Observable<Void>]()
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addClearHistoryMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInline, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInsideFolder, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxMenuItemTitleLength, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsTitleStartWithZero, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsAreMarkedWithNumbers, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showToolTipOnMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxLengthOfToolTip, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showColorPreviewInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        Observable.merge(menuChangedObservables)
            .throttle(.seconds(1), scheduler: MainScheduler.instance)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
    }
}

extension MenuManager {
    var hasHistoriesForStatusItemMenu: Bool {
        pasteboardHistoryRepository.hasHistories()
    }

    func refreshHistorySurfacesIfVisible() {
        mainMenuPanelController?.reloadContentIfVisible()
        historyPanelController?.reloadResultsIfVisible()
    }

    func refreshSnippetSurfacesIfVisible() {
        mainMenuPanelController?.reloadContentIfVisible()
        snippetPanelController?.reloadRowsIfVisible()
    }

    func refreshVisiblePanelBackgrounds() {
        mainMenuPanelController?.refreshAppearanceIfVisible()
        historyPanelController?.refreshAppearanceIfVisible()
        snippetPanelController?.refreshAppearanceIfVisible()
    }
}

// MARK: - Menus
extension MenuManager {
     func createClipMenu() {
        clipMenu = NSMenu(title: Constants.Application.name)
        historyMenu = nil
        snippetMenu = nil

        clipMenu?.addItem(makeHistoryBrowserMenuItem())
        clipMenu?.addItem(makeSnippetBrowserMenuItem())

        clipMenu?.addItem(NSMenuItem.separator())

        clipMenu?.addItem(NSMenuItem(title: String(localized: "Edit Snippets"), action: #selector(AppDelegate.showSnippetEditorWindow)))
        clipMenu?.addItem(NSMenuItem(title: String(localized: "Preferences"), action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu?.addItem(NSMenuItem.separator())
        clipMenu?.addItem(makeIconOnlyQuitMenuItem())

        statusItem?.menu = nil
    }

    private func makeIconOnlyQuitMenuItem() -> NSMenuItem {
        let accessibilityTitle = String(localized: "Quit Pastera")
        let item = NSMenuItem(title: "", action: #selector(AppDelegate.terminate), keyEquivalent: "")
        item.image = menuPanelSymbol("power", accessibilityDescription: accessibilityTitle)
        item.toolTip = accessibilityTitle
        return item
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = folderIcon
        return subMenuItem
    }

    func trimTitle(_ title: String?, minimumMaxLength: Int? = nil) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if let minimumMaxLength {
            maxMenuItemTitleLength = max(maxMenuItemTitleLength, minimumMaxLength)
        }
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }
}

// MARK: - Clips
extension MenuManager {
    func addHistoryItems(_ menu: NSMenu, asSubmenu: Bool) {
        if asSubmenu {
            menu.addItem(makeHistoryBrowserMenuItem())
        } else {
            configureHistoryBrowserMenu(menu)
        }
    }

    func makeHistoryBrowserMenuItem() -> NSMenuItem {
        let historyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let itemView = MainMenuHeaderItemView(
            title: String(localized: "History"),
            image: folderIcon,
            shortcutText: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.historyKeyCombo)
        )
        itemView.onOpen = { [weak self, weak historyItem] in
            historyItem?.menu?.cancelTracking()
            DispatchQueue.main.async { [weak self] in
                self?.showHistoryBrowserPanel(at: NSEvent.mouseLocation)
            }
        }
        historyItem.view = itemView
        return historyItem
    }

    @objc func openHistoryBrowserPanelFromMenuItem(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.showHistoryBrowserPanel(at: NSEvent.mouseLocation)
        }
    }

    func makeSnippetBrowserMenuItem() -> NSMenuItem {
        let snippetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let itemView = MainMenuHeaderItemView(
            title: String(localized: "Snippet"),
            image: snippetIcon,
            shortcutText: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.snippetKeyCombo)
        )
        itemView.onOpen = { [weak self, weak snippetItem] in
            snippetItem?.menu?.cancelTracking()
            DispatchQueue.main.async { [weak self] in
                self?.showSnippetBrowserPanel()
            }
        }
        itemView.onHoverOpen = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.showSnippetBrowserPanel()
            }
        }
        snippetItem.view = itemView
        return snippetItem
    }

    func currentMainMenuPasteTargetContext() -> PasteTargetContext? {
        mainMenuPanelController?.childPasteTargetContext
    }

    func showHistoryBrowserPanel(at screenPoint: NSPoint, triggerKeyCombo: KeyCombo? = nil) {
        snippetPanelController?.close()
        let panelController = historyPanelController ?? makeHistoryPanelController()
        historyPanelController = panelController
        if let mainMenuFrame = mainMenuPanelController?.visibleFrame {
            mainMenuPanelController?.beginChildPanelPresentation()
            panelController.setPinned(true)
            panelController.show(attachedTo: mainMenuFrame, pasteTargetContext: currentMainMenuPasteTargetContext())
        } else {
            panelController.setPinned(false)
            panelController.show(at: screenPoint, triggerKeyCombo: triggerKeyCombo)
        }
        installPanelDismissMonitorsIfNeeded()
    }

    func showMainMenuPanel(at screenPoint: NSPoint, pasteTargetContext: PasteTargetContext? = nil) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        panelController.show(at: screenPoint, pinned: false, pasteTargetContext: pasteTargetContext)
        installPanelDismissMonitorsIfNeeded()
    }

    func showMainMenuPanel(attachedToStatusItemFrame statusItemFrame: NSRect, pasteTargetContext: PasteTargetContext? = nil) {
        let panelController = mainMenuPanelController ?? makeMainMenuPanelController()
        mainMenuPanelController = panelController
        panelController.show(attachedToStatusItemFrame: statusItemFrame, pinned: false, pasteTargetContext: pasteTargetContext)
        installPanelDismissMonitorsIfNeeded()
    }

    func makeHistoryPanelController() -> HistoryBrowserPanelController {
        let controller = HistoryBrowserPanelController(
            currentState: { [weak self] in
                self?.historyMenuState ?? HistoryMenuPaginationState()
            },
            updateState: { [weak self] update in
                guard let self else { return }
                update(&self.historyMenuState)
            },
            fetchPage: { [weak self] in
                self?.fetchHistoryMenuPage() ?? HistoryMenuPage()
            },
            makeRowView: { [weak self] detail, index, onConfirm in
                self?.makeHistoryRowView(detail, index: index, onConfirm: onConfirm)
                    ?? HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
            },
            selectHistory: { [weak self] historyID, targetContext in
                self?.selectHistory(historyID, restoring: targetContext)
            }
        )
        controller.onClose = { [weak self] in
            self?.mainMenuPanelController?.endChildPanelPresentation()
        }
        controller.onMainMenuNavigationKeyDown = { [weak self] event in
            self?.mainMenuPanelController?.handleKeyboardNavigationFromChild(event) ?? false
        }
        return controller
    }

    // swiftlint:disable:next function_body_length
    func makeMainMenuPanelController() -> MainMenuPanelController {
        let syncFolderResolver = SyncDefaultFolderResolver()
        let syncSettingsStore = UserDefaultsSyncSettingsStore()
        let localOnlyFallback = LocalOnlyPasswordVaultSyncController(localVaultAvailable: false)
        return MainMenuPanelController(
            historyTitle: String(localized: "History"),
            historyImage: MainMenuModeIcons.history(),
            historyShortcutText: PasteraShortcutFormatter.string(for: AppEnvironment.current.hotKeyService.historyKeyCombo),
            snippetTitle: String(localized: "Snippet"),
            snippetImage: MainMenuModeIcons.snippets(),
            itemsProvider: { [weak self] in self?.makeMainMenuPanelItems() ?? [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { [weak self] in
                    self?.historyMenuState ?? HistoryMenuPaginationState()
                },
                updateState: { [weak self] update in
                    guard let self else { return }
                    update(&self.historyMenuState)
                },
                fetchPage: { [weak self] in
                    self?.fetchHistoryMenuPage() ?? HistoryMenuPage()
                },
                makeRowView: { [weak self] detail, index, onConfirm in
                    self?.makeHistoryRowView(detail, index: index, layoutStyle: .compactMainMenu, onConfirm: onConfirm)
                        ?? HistoryMenuRowView(title: detail.history.title, image: nil, layoutStyle: .compactMainMenu, onConfirm: onConfirm)
                },
                selectHistory: { [weak self] historyID, targetContext in
                    self?.selectHistory(historyID, restoring: targetContext)
                },
                fetchEditableText: { [weak self] historyID in
                    self?.editableTextHistoryContent(historyID)
                },
                updateTextHistory: { [weak self] historyID, text in
                    self?.pasteboardHistoryRepository.updateTextHistory(
                        id: historyID,
                        text: text,
                        updateAt: Int(Date().timeIntervalSince1970)
                    ) ?? false
                }
            ),
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: { [weak self] in
                    self?.snippetRepository.fetchFolderDetails() ?? []
                },
                fetchFolderDetail: { [weak self] folderID in
                    self?.snippetRepository.fetchFolderDetail(id: folderID)
                },
                selectSnippet: { [weak self] snippetID, targetContext in
                    self?.selectSnippet(snippetID, restoring: targetContext)
                },
                createFolder: { [weak self] title in
                    guard let self, let folder = self.snippetRepository.insertFolder() else { return nil }
                    guard self.snippetRepository.updateFolderTitle(folder.id, title: title) else {
                        self.snippetRepository.deleteFolder(folder.id)
                        return nil
                    }
                    return self.snippetRepository.fetchFolderDetail(id: folder.id)?.folder
                },
                createSnippet: { [weak self] folderID, title, content in
                    guard let self, let snippet = self.snippetRepository.insertSnippet(to: folderID) else { return nil }
                    guard content.isEmpty || self.snippetRepository.updateSnippetContent(snippet.id, content: content) else {
                        self.snippetRepository.deleteSnippet(snippet.id)
                        return nil
                    }
                    self.snippetRepository.updateSnippetTitle(snippet.id, title: title)
                    return self.snippetRepository.fetchFolderDetail(id: folderID)?.snippets.first { $0.id == snippet.id }
                },
                updateFolderTitle: { [weak self] folderID, title in
                    self?.snippetRepository.updateFolderTitle(folderID, title: title) ?? false
                },
                updateSnippetTitle: { [weak self] snippetID, title in
                    self?.snippetRepository.updateSnippetTitle(snippetID, title: title)
                },
                updateSnippetContent: { [weak self] snippetID, content in
                    self?.snippetRepository.updateSnippetContent(snippetID, content: content) ?? false
                },
                deleteFolder: { [weak self] folderID in
                    self?.snippetRepository.deleteFolder(folderID)
                    AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: folderID.uuidString)
                },
                deleteSnippet: { [weak self] snippetID in
                    self?.snippetRepository.deleteSnippet(snippetID)
                },
                reorderFolders: { [weak self] folderIDs in
                    self?.snippetRepository.reorderFolders(folderIDs) ?? false
                },
                moveSnippet: { [weak self] snippetID, folderID, orders in
                    self?.snippetRepository.moveSnippet(
                        snippetID,
                        to: folderID,
                        orderedSnippetIDsByFolder: orders
                    ) ?? false
                },
                folderKeyCombo: { folderID in
                    AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folderID.uuidString)
                },
                updateFolderKeyCombo: { folderID, keyCombo in
                    AppEnvironment.current.hotKeyService.registerSnippetHotKey(
                        with: folderID.uuidString,
                        keyCombo: keyCombo
                    )
                },
                clearFolderKeyCombo: { folderID in
                    AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: folderID.uuidString)
                }
            ),
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                state: { [weak self] in self?.passwordVaultUIController.state ?? .failed("unavailable") },
                checkQuickUnlockAvailability: { [weak self] completion in
                    self?.passwordVaultUIController.checkQuickUnlockAvailability(completion: completion)
                },
                createDatabase: { [weak self] password, completion in
                    self?.passwordVaultUIController.createDatabase(masterPassword: password, completion: completion)
                },
                unlock: { [weak self] password, completion in
                    self?.passwordVaultUIController.unlock(masterPassword: password, completion: completion)
                },
                unlockWithQuickKey: { [weak self] completion in
                    self?.passwordVaultUIController.unlockWithQuickKey(completion: completion)
                },
                retryLocalPreparation: {
                    AppEnvironment.current.retryPasswordVaultLocalPreparation()
                },
                fetchFolders: { [weak self] in
                    try self?.passwordVaultUIController.folders() ?? []
                },
                fetchEntries: { [weak self] in
                    try self?.passwordVaultUIController.entries() ?? []
                },
                copyPassword: { [weak self] id, completion in
                    self?.passwordVaultUIController.copyPassword(id: id, completion: completion)
                },
                pasteUsername: { [weak self] id, context, completion in
                    self?.passwordVaultUIController.pasteUsername(id: id, targetContext: context, completion: completion)
                },
                pastePassword: { [weak self] id, context, completion in
                    self?.passwordVaultUIController.pastePassword(id: id, targetContext: context, completion: completion)
                },
                loadDraft: { [weak self] id, completion in
                    self?.passwordVaultUIController.loadDraft(id: id, completion: completion)
                },
                createEntry: { [weak self] draft, completion in
                    self?.passwordVaultUIController.createEntry(draft, completion: completion)
                },
                updateEntry: { [weak self] id, draft, completion in
                    self?.passwordVaultUIController.updateEntry(id: id, draft: draft, completion: completion)
                },
                deleteEntry: { [weak self] id, completion in
                    self?.passwordVaultUIController.deleteEntry(id: id, completion: completion)
                },
                createFolder: { _ in throw PasswordVaultError.keychainUnavailable },
                renameFolder: { _, _ in throw PasswordVaultError.keychainUnavailable },
                deleteFolder: { _ in throw PasswordVaultError.keychainUnavailable },
                createFolderAsync: { [weak self] name, completion in
                    self?.passwordVaultUIController.createFolder(name: name, completion: completion)
                },
                renameFolderAsync: { [weak self] id, name, completion in
                    self?.passwordVaultUIController.renameFolder(id: id, name: name, completion: completion)
                },
                deleteFolderAsync: { [weak self] id, completion in
                    self?.passwordVaultUIController.deleteFolder(id: id, completion: completion)
                },
                reorderFolders: { [weak self] folderIDs, completion in
                    self?.passwordVaultUIController.reorderFolders(folderIDs, completion: completion)
                },
                moveEntry: { [weak self] id, folderID, orders, completion in
                    self?.passwordVaultUIController.moveEntry(
                        id: id,
                        to: folderID,
                        orderedEntryIDsByFolder: orders,
                        completion: completion
                    )
                }
            ),
            passwordVaultSyncDataSource: MainMenuPasswordVaultSyncDataSource(
                snapshot: { [weak self] in
                    self?.passwordVaultSyncSnapshot
                        ?? self?.passwordVaultSyncService.snapshot
                        ?? localOnlyFallback.snapshot
                },
                enableConfiguredOneDrive: { [weak self] remoteMasterPassword, completion in
                    guard let self else {
                        completion(.failure(.remoteUnavailable))
                        return
                    }
                    guard let rootURL = syncSettingsStore.settings().rootURL,
                          syncFolderResolver.oneDriveCandidate(containing: rootURL) != nil else {
                        completion(.failure(.folderUnavailable))
                        return
                    }
                    self.passwordVaultSyncService.enableOneDrive(
                        rootURL: rootURL,
                        remoteMasterPassword: remoteMasterPassword,
                        completion: completion
                    )
                },
                retryWithRemotePassword: { [weak self] password, completion in
                    guard let self else {
                        completion(.failure(.remoteUnavailable))
                        return
                    }
                    self.passwordVaultSyncService.retry(
                        remoteMasterPassword: password,
                        completion: completion
                    )
                },
                startOneDrive: {
                    AppEnvironment.current.oneDriveProcessStatusService.openOneDrive()
                }
            ),
            oneDriveStatusService: AppEnvironment.current.oneDriveProcessStatusService,
            onOpenPreferences: {
                (NSApp.delegate as? AppDelegate)?.showPreferenceWindow()
            },
            onOpenOneDriveStatus: {
                (NSApp.delegate as? AppDelegate)?.showSyncPreferencePane()
            },
            onCloseChildPanels: {}
        )
    }

    func makeMainMenuPanelItems() -> [MainMenuPanelItem] {
        var items = [MainMenuPanelItem]()

        if secureEventInputEnabledProvider() {
            items.append(.notice(
                title: String(localized: "Shortcuts are paused"),
                message: String(localized: "macOS paused global shortcuts while Secure Keyboard Entry is active. Click the Pastera menu bar icon to open Pastera."),
                image: menuPanelSymbol(
                    "exclamationmark.triangle.fill",
                    accessibilityDescription: String(localized: "Secure Keyboard Entry")
                )
            ))
            items.append(.separator)
        }

        let enabledSnippetFolders = snippetRepository.fetchFolders()
            .filter(\.isEnabled)
        if !enabledSnippetFolders.isEmpty {
            let folderImage = folderIcon
            enabledSnippetFolders.forEach { folder in
                let title = trimTitle(folder.title)
                let shortcutText = PasteraShortcutFormatter.string(
                    for: AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.id.uuidString)
                )
                items.append(.snippetFolder(title: title, image: folderImage, shortcutText: shortcutText) { [weak self] _ in
                    guard let self,
                          let detail = self.snippetRepository.fetchFolderDetail(id: folder.id) else { return }
                    self.popUpSnippetFolder(detail)
                })
            }
            items.append(.separator)
        }

        return items
    }

    private func menuPanelSymbol(_ name: String, accessibilityDescription: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }

    func makeSnippetPanelController() -> SnippetBrowserPanelController {
        let controller = SnippetBrowserPanelController(
            fetchFolders: { [weak self] in
                self?.snippetRepository.fetchFolders() ?? []
            },
            fetchFolderDetail: { [weak self] folderID in
                self?.snippetRepository.fetchFolderDetail(id: folderID)
            },
            selectSnippet: { [weak self] snippetID, targetContext in
                self?.selectSnippet(snippetID, restoring: targetContext)
            }
        )
        controller.onClose = { [weak self] in
            self?.mainMenuPanelController?.endChildPanelPresentation()
        }
        controller.onMainMenuNavigationKeyDown = { [weak self] event in
            self?.mainMenuPanelController?.handleKeyboardNavigationFromChild(event) ?? false
        }
        return controller
    }

    func showSnippetBrowserPanel() {
        historyPanelController?.close()
        guard let mainMenuFrame = mainMenuPanelController?.visibleFrame else {
            showSnippetBrowserPanel(at: NSEvent.mouseLocation)
            return
        }

        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        mainMenuPanelController?.beginChildPanelPresentation()
        panelController.show(attachedTo: mainMenuFrame, pasteTargetContext: currentMainMenuPasteTargetContext())
        installPanelDismissMonitorsIfNeeded()
    }

    func showSnippetBrowserPanel(at screenPoint: NSPoint, triggerKeyCombo: KeyCombo? = nil) {
        historyPanelController?.close()
        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        panelController.show(at: screenPoint, triggerKeyCombo: triggerKeyCombo)
        installPanelDismissMonitorsIfNeeded()
    }

    func showSnippetFolderPanel(_ folderID: SnippetFolder.ID, attachedTo anchorFrame: NSRect?) {
        historyPanelController?.close()
        guard let anchorFrame = anchorFrame ?? mainMenuPanelController?.visibleFrame else {
            showSnippetFolderPanel(folderID, at: NSEvent.mouseLocation)
            return
        }

        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        mainMenuPanelController?.beginChildPanelPresentation()
        panelController.show(folderID: folderID, attachedTo: anchorFrame, pasteTargetContext: currentMainMenuPasteTargetContext())
        installPanelDismissMonitorsIfNeeded()
    }

    func showSnippetFolderPanel(
        _ folderID: SnippetFolder.ID,
        at screenPoint: NSPoint,
        triggerKeyCombo: KeyCombo? = nil
    ) {
        historyPanelController?.close()
        let panelController = snippetPanelController ?? makeSnippetPanelController()
        snippetPanelController = panelController
        panelController.show(folderID: folderID, at: screenPoint, triggerKeyCombo: triggerKeyCombo)
        installPanelDismissMonitorsIfNeeded()
    }

    func makeHistoryBrowserMenu() -> NSMenu {
        let menu = HistoryBrowserMenu(title: String(localized: "History"))
        configureHistoryBrowserMenu(menu)
        return menu
    }

    func configureHistoryBrowserMenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        while menu.numberOfItems > 0 {
            menu.removeItem(at: 0)
        }

        let headerView = HistoryMenuHeaderView()
        let headerItem = NSMenuItem()
        headerItem.view = headerView
        (menu as? HistoryBrowserMenu)?.headerView = headerView
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        let updateMenu = { [weak self, weak menu, weak headerView] (update: (inout HistoryMenuPaginationState) -> Void) in
            self?.updateHistoryBrowserMenu(menu, headerView: headerView, update: update)
        }
        headerView.onQueryChange = { query in updateMenu { $0.updateQuery(query) } }
        headerView.onModeChange = { mode in updateMenu { $0.updateMode(mode) } }
        headerView.onCaseSensitiveChange = { caseSensitive in updateMenu { $0.updateCaseSensitive(caseSensitive) } }
        headerView.onTypeFilterChange = { typeFilter in updateMenu { $0.updateTypeFilter(typeFilter) } }
        headerView.onPreviousPage = { updateMenu { $0.goToPreviousPage() } }
        headerView.onNextPage = { [weak self, weak menu, weak headerView] in
            guard let self = self else { return }
            let page = self.fetchHistoryMenuPage()
            self.updateHistoryBrowserMenu(menu, headerView: headerView) { $0.goToNextPage(if: page.hasNextPage) }
        }

        reloadHistoryBrowserResults(in: menu, headerView: headerView)
    }

    func updateHistoryBrowserMenu(_ menu: NSMenu?, headerView: HistoryMenuHeaderView?, update: (inout HistoryMenuPaginationState) -> Void) {
        update(&historyMenuState)
        guard let menu = menu else { return }
        reloadHistoryBrowserResults(in: menu, headerView: headerView)
    }

    func reloadHistoryBrowserResults(in menu: NSMenu, headerView: HistoryMenuHeaderView?) {
        HistoryMenuRowView.hideImagePreview()
        while menu.numberOfItems > 2 {
            menu.removeItem(at: 2)
        }

        var page = fetchHistoryMenuPage()
        if page.details.isEmpty && page.error == nil && historyMenuState.pageIndex > 0 {
            historyMenuState.resetPage()
            page = fetchHistoryMenuPage()
        }

        headerView?.configure(state: historyMenuState, hasNextPage: page.hasNextPage)

        if let error = page.error {
            let errorItem = NSMenuItem(title: error.historyMenuTitle, action: nil)
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            headerView?.connectKeyboardNavigation(to: [])
            return
        }

        guard !page.details.isEmpty else {
            let title = historyMenuState.hasActiveSearchOptions ? String(localized: "No Results") : String(localized: "No History")
            let emptyItem = NSMenuItem(title: title, action: nil)
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            headerView?.connectKeyboardNavigation(to: [])
            return
        }

        let firstIndex = firstIndexOfMenuItems()
        var historyRowViews = [HistoryMenuRowView]()
        for (index, historyDetail) in page.details.enumerated() {
            let listNumber = (firstIndex + index) % kMaxKeyEquivalents
            let menuItem = makeClipMenuItem(historyDetail, index: index, listNumber: listNumber)
            menu.addItem(menuItem)
            if let rowView = menuItem.view as? HistoryMenuRowView {
                historyRowViews.append(rowView)
            }
        }
        headerView?.connectKeyboardNavigation(to: historyRowViews)
    }

    private func currentHistorySearchQuery() -> HistorySearchQuery {
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        return HistorySearchQuery(
            text: historyMenuState.query,
            mode: historyMenuState.mode,
            caseSensitive: historyMenuState.caseSensitive,
            types: historyMenuState.selectedTypes,
            fileCategories: historyMenuState.selectedFileCategories,
            sortOrder: ascending ? .oldestFirst : .newestFirst,
            groupsEquivalentText: AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
        )
    }

    func fetchHistoryMenuPage() -> HistoryMenuPage {
        let limit = historyMenuState.pageSize + 1
        let query = currentHistorySearchQuery()
        do {
            let details = try pasteboardHistoryRepository.searchHistoryDetails(
                query: query,
                includesThumbnailAsset: true,
                limit: limit,
                offset: historyMenuState.offset
            )
            return .result(details, pageSize: historyMenuState.pageSize)
        } catch let error as HistorySearchError {
            return HistoryMenuPage(error: error)
        } catch {
            return HistoryMenuPage()
        }
    }

    func makeClipMenuItem(_ historyDetail: PasteboardHistoryDetail, index: Int, listNumber: Int) -> NSMenuItem {
        let history = historyDetail.history
        let shortcutText = numericShortcutText(forRowIndex: index)
        let presentation = makeHistoryItemPresentation(
            historyDetail,
            listNumber: listNumber,
            usesLeadingNumber: false
        )

        let menuItem = NSMenuItem(
            title: presentation.title,
            action: #selector(AppDelegate.selectClipMenuItem(_:)),
            keyEquivalent: shortcutText ?? ""
        )
        menuItem.representedObject = history.id

        if let toolTip = presentation.toolTip {
            menuItem.toolTip = toolTip
        }

        menuItem.image = presentation.image

        menuItem.view = HistoryMenuRowView(
            title: menuItem.title,
            image: menuItem.image,
            shortcutText: shortcutText,
            previewText: presentation.previewText,
            onDelete: { [weak self, weak menuItem] in
                menuItem?.menu?.cancelTracking()
                self?.deleteHistory(history.id)
            },
            onConfirm: { [weak menuItem] in
                guard let menuItem else { return }
                menuItem.menu?.cancelTracking()
                DispatchQueue.main.async {
                    NSApp.sendAction(#selector(AppDelegate.selectClipMenuItem(_:)), to: nil, from: menuItem)
                }
            }
        )

        return menuItem
    }

    func makeHistoryRowView(_ historyDetail: PasteboardHistoryDetail, index: Int, layoutStyle: HistoryMenuRowView.LayoutStyle = .regular, onConfirm: @escaping () -> Void) -> HistoryMenuRowView {
        let listNumber = (firstIndexOfMenuItems() + index) % kMaxKeyEquivalents
        let shortcutText = numericShortcutText(forRowIndex: index)
        let presentation = makeHistoryItemPresentation(
            historyDetail,
            listNumber: listNumber,
            usesLeadingNumber: false,
            usesCompactImageLabel: layoutStyle == .compactMainMenu
        )
        let onEdit: (() -> Void)? = isHistoryEditorSupported(historyDetail.history.pasteboardTypes)
            ? { [weak self] in self?.openHistoryEditor(historyDetail.history.id) }
            : nil
        let onQuickEdit: (() -> Void)? = layoutStyle == .compactMainMenu &&
            isEditablePlainTextHistoryTypes(historyDetail.history.pasteboardTypes)
            ? { [weak self] in self?.mainMenuPanelController?.beginEditingHistory(historyDetail.history.id) }
            : nil
        let scriptActions = makeHistoryScriptActions(
            historyID: historyDetail.history.id,
            pasteboardTypes: historyDetail.history.pasteboardTypes,
            layoutStyle: layoutStyle
        )
        return HistoryMenuRowView(
            title: presentation.title,
            image: presentation.image,
            shortcutText: shortcutText,
            previewText: presentation.previewText,
            layoutStyle: layoutStyle,
            onEdit: onEdit,
            onQuickEdit: onQuickEdit,
            onDelete: { [weak self] in self?.deleteHistory(historyDetail.history.id) },
            scriptActions: scriptActions,
            onConfirm: onConfirm
        )
    }

    private func makeHistoryScriptActions(
        historyID: PasteboardHistory.ID,
        pasteboardTypes: [NSPasteboard.PasteboardType],
        layoutStyle: HistoryMenuRowView.LayoutStyle
    ) -> [HistoryScriptAction] {
        guard isEditablePlainTextHistoryTypes(pasteboardTypes) else { return [] }
        let coordinator = AppEnvironment.current.clipboardScriptCoordinator
        return coordinator.availableHistoryScripts().map { script in
            let target = layoutStyle == .compactMainMenu
                ? mainMenuPanelController?.childPasteTargetContext
                : historyPanelController?.childPasteTargetContext
            let closeSurface = { [weak self] in
                if layoutStyle == .compactMainMenu {
                    self?.mainMenuPanelController?.close()
                } else {
                    self?.historyPanelController?.close()
                }
            }
            let perform: (@escaping (String) -> Void, @escaping (ScriptExecutionError) -> Void) -> Void = { [weak self] completion, failure in
                guard let text = self?.editableTextHistoryContent(historyID) else { return }
                Task {
                    let outcome = await coordinator.transformHistoryText(
                        text,
                        using: script.id,
                        sourceAppBundleIdentifier: target?.bundleIdentifier
                    )
                    let output: String
                    switch outcome {
                    case let .transformed(transformed): output = transformed
                    case .unchanged: output = text
                    case let .failed(error):
                        await MainActor.run { failure(error) }
                        return
                    }
                    await MainActor.run { completion(output) }
                }
            }
            return HistoryScriptAction(
                id: script.id,
                title: script.name,
                copy: {
                    closeSurface()
                    perform({ output in
                        coordinator.writeHistoryTransformResult(output)
                        HistoryScriptFeedbackPresenter.shared.show(.copied(scriptName: script.name))
                    }, { error in
                        HistoryScriptFeedbackPresenter.shared.show(.failed(scriptName: script.name, error: error))
                    })
                },
                paste: {
                    closeSurface()
                    perform({ output in
                        AppEnvironment.current.pasteService.pasteResolvedScriptText(output, restoring: target)
                        HistoryScriptFeedbackPresenter.shared.show(.pasted(scriptName: script.name))
                    }, { error in
                        HistoryScriptFeedbackPresenter.shared.show(.failed(scriptName: script.name, error: error))
                    })
                }
            )
        }
    }

    func makeHistoryItemPresentation(
        _ historyDetail: PasteboardHistoryDetail,
        listNumber: Int,
        usesLeadingNumber: Bool? = nil,
        usesCompactImageLabel: Bool = false
    ) -> HistoryItemPresentation {
        let history = historyDetail.history
        let isMarkWithNumber = usesLeadingNumber ?? false
        let isShowToolTip = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let primaryPboardType = history.primaryType
        let clipString = history.title
        let displayTitle = trimTitle(clipString)
        var previewText = textPreviewText(
            originalTitle: clipString,
            displayedTitle: displayTitle,
            primaryPboardType: primaryPboardType
        )
        var fallbackImage: NSImage?
        var title = menuItemTitle(
            displayTitle,
            listNumber: listNumber,
            isMarkWithNumber: isMarkWithNumber
        )

        if primaryPboardType?.isClipyImageType == true {
            let imageTitle = usesCompactImageLabel ? String(localized: "Image") : "(Image)"
            title = menuItemTitle(imageTitle, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
            previewText = nil
        } else if primaryPboardType == .pdf || primaryPboardType == .deprecatedPDF {
            title = menuItemTitle("(PDF)", listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
            previewText = nil
        } else if primaryPboardType == .fileURL {
            let filePresentation = fileURLPresentation(from: clipString)
            let fileTitle = filePresentation?.title ?? "其他文件"
            title = menuItemTitle(
                trimTitle(fileTitle),
                listNumber: listNumber,
                isMarkWithNumber: isMarkWithNumber
            )
            previewText = filePresentation?.previewText
            fallbackImage = PasteraFinderFileCategory.category(forFilename: fileTitle).icon()
        }

        let toolTip: String?
        if isShowToolTip {
            let maxLengthOfToolTip = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
            let toIndex = (clipString.count < maxLengthOfToolTip) ? clipString.count : maxLengthOfToolTip
            toolTip = (clipString as NSString).substring(to: toIndex)
        } else {
            toolTip = nil
        }

        let image: NSImage?
        if let thumbnailAsset = historyDetail.thumbnailAsset,
           let thumbnailImage = NSImage(data: thumbnailAsset.data),
           thumbnailAsset.kind == .image || (thumbnailAsset.kind == .colorCode && isShowColorCode) {
            image = thumbnailImage
        } else if let fallbackImage {
            image = fallbackImage
        } else {
            image = nil
        }

        return HistoryItemPresentation(title: title, image: image, toolTip: toolTip, previewText: previewText)
    }

    private func fileURLPresentation(from title: String) -> (title: String, previewText: String?)? {
        var lines = title.components(separatedBy: .newlines)
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !firstLine.isEmpty else {
            return nil
        }
        lines.removeFirst()
        let previewText = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (firstLine, previewText.isEmpty ? nil : previewText)
    }

    private func textPreviewText(
        originalTitle: String,
        displayedTitle: String,
        primaryPboardType: NSPasteboard.PasteboardType?
    ) -> String? {
        if primaryPboardType?.isClipyImageType == true ||
            primaryPboardType == .pdf ||
            primaryPboardType == .deprecatedPDF ||
            primaryPboardType == .fileURL {
            return nil
        }

        let previewText = originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previewText.isEmpty, previewText != displayedTitle else { return nil }
        return previewText
    }

    func numericShortcutText(forRowIndex index: Int) -> String? {
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        return PasteraShortcutFormatter.numericString(forRowIndex: index, startsAtZero: startsAtZero)
    }

    func selectHistory(_ historyID: PasteboardHistory.ID, restoring targetContext: PasteTargetContext?) {
        dismissMenuPanelsAfterSelection()

        let menuItem = NSMenuItem(title: "", action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = PasteboardHistorySelectionRequest(id: historyID, targetContext: targetContext)

        selectionActionScheduler(SelectionActionMetrics.delay) {
            NSApp.sendAction(#selector(AppDelegate.selectClipMenuItem(_:)), to: nil, from: menuItem)
        }
    }

    func deleteHistory(_ historyID: PasteboardHistory.ID) {
        withErrorReporting {
            try pasteboardHistoryRepository.deleteDisplayedHistory(id: historyID, query: currentHistorySearchQuery())
        }
    }

    func editableTextHistoryContent(_ historyID: PasteboardHistory.ID) -> String? {
        guard let history = pasteboardHistoryRepository.fetchHistory(id: historyID),
              isEditablePlainTextHistoryTypes(history.pasteboardTypes),
              let content = pasteboardHistoryRepository.fetchContent(id: historyID) else {
            return nil
        }
        return content.stringValue
    }

    private func openHistoryEditor(_ historyID: PasteboardHistory.ID) {
        mainMenuPanelController?.close()
        historyPanelController?.close()
        historyEditorWindowController.show(historyID: historyID)
    }

    private func isHistoryEditorSupported(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        isEditablePlainTextHistoryTypes(types) || types.contains(where: { $0.isClipyImageType })
    }

    private func isEditablePlainTextHistoryTypes(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        guard !types.isEmpty else { return false }
        let plainTextTypes: Set<NSPasteboard.PasteboardType> = [.string, .deprecatedString]
        return Set(types).isSubset(of: plainTextTypes)
    }
}

extension MenuManager {
    func showMainMenuPanelFromStatusItemFrame(_ statusItemFrame: NSRect?) {
        guard let statusItemFrame else {
            showMainMenuPanel(at: NSEvent.mouseLocation)
            return
        }
        showMainMenuPanel(attachedToStatusItemFrame: statusItemFrame)
    }
}

// MARK: - Snippets
extension MenuManager {
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        let details = snippetRepository.fetchFolderDetails()
        guard !details.isEmpty else { return }

        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        // Snippet title
        let labelItem = NSMenuItem(title: String(localized: "Snippet"), action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        var subMenuIndex = menu.numberOfItems - 1
        let firstIndex = firstIndexOfMenuItems()
        details
            .filter { $0.folder.isEnabled }
            .forEach { detail in
                let folderTitle = detail.folder.title
                let subMenuItem = makeSubmenuItem(folderTitle)
                menu.addItem(subMenuItem)
                subMenuIndex += 1

                detail.snippets
                    .filter { $0.isEnabled }
                    .enumerated()
                    .forEach { rowIndex, snippet in
                        let subMenuItem = makeSnippetMenuItem(snippet, listNumber: firstIndex + rowIndex, rowIndex: rowIndex)
                        if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                            subMenu.addItem(subMenuItem)
                        }
                    }
            }
    }

    func makeSnippetMenuItem(_ snippet: Snippet, listNumber: Int, rowIndex: Int) -> NSMenuItem {
        let shortcutText = numericShortcutText(forRowIndex: rowIndex)

        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: false)

        let menuItem = NSMenuItem(
            title: titleWithMark,
            action: #selector(AppDelegate.selectSnippetMenuItem(_:)),
            keyEquivalent: shortcutText ?? ""
        )
        menuItem.representedObject = snippet.id
        menuItem.toolTip = snippet.content
        menuItem.image = snippetIcon
        menuItem.keyEquivalentModifierMask = []

        return menuItem
    }

    func selectSnippet(_ snippetID: Snippet.ID, restoring targetContext: PasteTargetContext?) {
        dismissMenuPanelsAfterSelection()

        let menuItem = NSMenuItem(title: "", action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = SnippetSelectionRequest(id: snippetID, targetContext: targetContext)

        selectionActionScheduler(SelectionActionMetrics.delay) {
            NSApp.sendAction(#selector(AppDelegate.selectSnippetMenuItem(_:)), to: nil, from: menuItem)
        }
    }
}

// MARK: - Settings
extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}
