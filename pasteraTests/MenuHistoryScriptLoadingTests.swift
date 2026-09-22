import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MenuHistoryScriptLoadingTests {
    @Test(arguments: [false, true])
    func buildingHistoryRowDoesNotReadFullContent(hasScripts: Bool) throws {
        let repository = ScriptRowHistoryRepository()
        let coordinator = ScriptRowCoordinator(hasScripts: hasScripts)
        let (manager, row) = makeRow(repository: repository, coordinator: coordinator)

        let menu = try #require(row.menu(for: try contextMenuEvent()))
        let copyAs = menu.items.first { $0.title == pasteraScriptString("Copy As", "复制为") }
        #expect((copyAs != nil) == hasScripts)
        #expect(repository.historyReadCount == 0)
        #expect(repository.contentReadCount == 0)
        withExtendedLifetime(manager) {}
    }

    @Test
    func executingHistoryScriptReadsTextUpdatedAfterRowWasBuilt() async throws {
        let repository = ScriptRowHistoryRepository()
        let coordinator = ScriptRowCoordinator(hasScripts: true)
        let (manager, row) = makeRow(repository: repository, coordinator: coordinator)
        repository.text = "Updated after menu opened"
        let menu = try #require(row.menu(for: try contextMenuEvent()))
        let copyAs = try #require(menu.items.first {
            $0.title == pasteraScriptString("Copy As", "复制为")
        })
        let item = try #require(copyAs.submenu?.items.first)
        let action = try #require(item.action)

        let writtenText = await withCheckedContinuation { continuation in
            coordinator.onWrite = { continuation.resume(returning: $0) }
            NSApp.sendAction(action, to: item.target, from: item)
        }

        #expect(writtenText == "Updated after menu opened")
        #expect(coordinator.transformedText == "Updated after menu opened")
        #expect(repository.contentReadCount == 1)
        withExtendedLifetime(manager) {}
        withExtendedLifetime(row) {}
    }

    private func makeRow(
        repository: ScriptRowHistoryRepository,
        coordinator: ScriptRowCoordinator
    ) -> (MenuManager, HistoryMenuRowView) {
        AppEnvironment.push(clipboardScriptCoordinator: coordinator)
        defer { _ = AppEnvironment.popLast() }
        return withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let manager = MenuManager()
            let detail = PasteboardHistoryDetail(history: repository.history, thumbnailAsset: nil)
            let row = manager.makeHistoryRowView(detail, index: 0, onConfirm: {})
            return (manager, row)
        }
    }

    private func contextMenuEvent() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
    }
}

private final class ScriptRowHistoryRepository: PasteboardHistoryRepositoryProtocol {
    let history = PasteboardHistory(
        id: PasteboardHistory.ID("script-row"),
        title: "Original text",
        pasteboardTypes: [.string],
        updateAt: 1,
        deviceID: nil
    )
    var text = "Original text"
    private(set) var historyReadCount = 0
    private(set) var contentReadCount = 0

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([history]).eraseToAnyPublisher()
    }
    func hasHistories() -> Bool { true }
    func fetchHistoryDetails(ascending: Bool, includesThumbnailAsset: Bool, limit: Int, offset: Int) -> [PasteboardHistoryDetail] { [] }
    func searchHistoryDetails(query: HistorySearchQuery, includesThumbnailAsset: Bool, limit: Int, offset: Int) throws -> [PasteboardHistoryDetail] { [] }
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? {
        historyReadCount += 1
        return id == history.id ? history : nil
    }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? {
        contentReadCount += 1
        guard id == history.id else { return nil }
        return PasteboardContent(assets: [.init(type: .string, data: Data(text.utf8))])
    }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

final class ScriptRowCoordinator: ClipboardScriptCoordinating {
    private let scripts: [ScriptTransform]
    private(set) var transformedText: String?
    var onWrite: ((String) -> Void)?

    init(hasScripts: Bool) {
        scripts = hasScripts ? [ScriptTransform(
            id: UUID(), name: "Identity", code: "function transform(clip) { return clip.text; }",
            isEnabled: true, runOnCopy: false, runOnPaste: false, runManually: true,
            sortIndex: 0, createdAt: 1, updatedAt: 1
        )] : []
    }
    func hasEnabledScripts(for trigger: ScriptTrigger) -> Bool { !scripts.isEmpty }
    func availableHistoryScripts() -> [ScriptTransform] { scripts }
    func transform(text: String, sourceAppBundleIdentifier: String?, trigger: ScriptTrigger) async -> ScriptTransformOutcome { .unchanged }
    func transformHistoryText(_ text: String, using scriptID: UUID, sourceAppBundleIdentifier: String?) async -> ScriptTransformOutcome {
        transformedText = text
        return .unchanged
    }
    func writeHistoryTransformResult(_ text: String) { onWrite?(text) }
    func runManualTransform() async {}
    func consumeSuppression(changeCount: Int) -> Bool { false }
}
