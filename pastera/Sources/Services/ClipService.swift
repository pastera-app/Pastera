//
//  ClipService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Dependencies
import Foundation
import PINCache
import RxSwift
import RxCocoa

final class ClipService {

    // MARK: - Properties
    fileprivate var cachedChangeCount = BehaviorRelay<Int>(value: 0)
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .utility)
    fileprivate let lock = NSRecursiveLock(name: "com.pastera-app.Pastera.ClipUpdatable")
    fileprivate var ignoredPasteboardChangeCounts = Set<Int>()
    fileprivate var disposeBag = DisposeBag()
    private let clipboardScriptCoordinatorProvider: () -> ClipboardScriptCoordinating?
    private let sourceAppBundleIdentifierProvider: () -> String?

    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository
    @Dependency(\.pasteboardHistoryOCRIndexer)
    private var pasteboardHistoryOCRIndexer

    init(
        clipboardScriptCoordinatorProvider: @escaping () -> ClipboardScriptCoordinating? = { nil },
        sourceAppBundleIdentifierProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.clipboardScriptCoordinatorProvider = clipboardScriptCoordinatorProvider
        self.sourceAppBundleIdentifierProvider = sourceAppBundleIdentifierProvider
    }

    // MARK: - Clips
    func startMonitoring() {
        disposeBag = DisposeBag()
        // Pasteboard observe timer
        Observable<Int>.interval(.milliseconds(750), scheduler: scheduler)
            .map { _ in NSPasteboard.general.changeCount }
            .withLatestFrom(cachedChangeCount.asObservable()) { ($0, $1) }
            .filter { $0 != $1 }
            .subscribe(onNext: { [weak self] changeCount, _ in
                guard self?.create() == true else { return }
                self?.cachedChangeCount.accept(changeCount)
            })
            .disposed(by: disposeBag)
        // Store types
        AppEnvironment.current.defaults.rx
            .observe([String: NSNumber].self, Constants.UserDefaults.storeTypes)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.storeTypes = $0
            })
            .disposed(by: disposeBag)
    }

    func clearAll() {
        pasteboardHistoryRepository.deleteAll()
        // Clear legacy Realm-backed history caches used through v1.2.1.
        PINCache.shared.removeAllObjects()
        try? FileManager.default.removeItem(atPath: CPYUtilities.applicationSupportFolder())
    }

    func delete(with history: PasteboardHistory) {
        pasteboardHistoryRepository.deleteHistory(id: history.id)
    }

    func incrementChangeCount() {
        cachedChangeCount.accept(cachedChangeCount.value + 1)
    }

    func ignorePasteboardChange(_ changeCount: Int) {
        lock.lock(); defer { lock.unlock() }
        ignoredPasteboardChangeCounts.insert(changeCount)
    }

}

// MARK: - Create Clip
extension ClipService {
    @discardableResult
    fileprivate func create(from pasteboard: NSPasteboard = .general) -> Bool {
        lock.lock(); defer { lock.unlock() }

        if ignoredPasteboardChangeCounts.remove(pasteboard.changeCount) != nil {
            return true
        }

        // Pasteboard types
        let pasteboardTypes = pasteboard.pasteboardItems?.flatMap { $0.types } ?? []
        guard !pasteboardTypes.isEmpty else { return false }
        guard SecurePasteboardTypes.all.isDisjoint(with: pasteboardTypes) else { return true }
        let types = PasteboardAvailableType.availableTypes(
            from: pasteboardTypes,
            storeAvailableTypes: storeTypes.filter { $0.value.boolValue }.compactMap { PasteboardAvailableType(rawValue: $0.key) }
        )
        guard !types.isEmpty else { return true }

        // Excluded application
        guard !AppEnvironment.current.excludeAppService.frontProcessIsExcludedApplication() else { return true }
        // Special applications
        guard !AppEnvironment.current.excludeAppService.copiedProcessIsExcludedApplications(pasteboard: pasteboard) else { return true }

        guard let content = PasteboardContent(pasteboard: pasteboard, types: types) else { return false }
        if content.isOnlyStringType,
           let coordinator = clipboardScriptCoordinatorProvider(),
           coordinator.hasEnabledScripts(for: .copy) {
            transformAndSave(
                content,
                pasteboard: pasteboard,
                coordinator: coordinator,
                sourceAppBundleIdentifier: sourceAppBundleIdentifierProvider()
            )
            return true
        }
        return save(content)
    }

    private func transformAndSave(
        _ originalContent: PasteboardContent,
        pasteboard: NSPasteboard,
        coordinator: ClipboardScriptCoordinating,
        sourceAppBundleIdentifier: String?
    ) {
        Task { [weak self] in
            guard let self else { return }
            let outcome = await coordinator.transform(
                text: originalContent.stringValue,
                sourceAppBundleIdentifier: sourceAppBundleIdentifier,
                trigger: .copy
            )
            self.lock.lock()
            defer { self.lock.unlock() }
            switch outcome {
            case .unchanged, .failed:
                self.save(originalContent)
            case let .transformed(output):
                pasteboard.clearContents()
                pasteboard.setString(output, forType: .string)
                self.ignoredPasteboardChangeCounts.insert(pasteboard.changeCount)
                self.save(
                    PasteboardContent(
                        assets: [.init(type: .string, data: Data(output.utf8))]
                    )
                )
            }
        }
    }

    func create(with image: NSImage) {
        lock.lock(); defer { lock.unlock() }

        guard let content = PasteboardContent(image: image) else { return }
        save(content, allowDuplicateContent: true)
    }

    func createScreenshot(from url: URL) {
        lock.lock(); defer { lock.unlock() }

        guard let content = PasteboardContent(imageFileURL: url) else { return }
        save(content, allowDuplicateContent: true)
    }

    @discardableResult
    private func save(_ content: PasteboardContent, allowDuplicateContent: Bool = false) -> Bool {
        // Copy already copied history
        let isCopySameHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory)
        let historyID = PasteboardHistory.ID(rawValue: content.hash)
        let matchingHistory = allowDuplicateContent ? nil : pasteboardHistoryRepository.fetchHistory(matching: content)
        if matchingHistory != nil, !isCopySameHistory { return true }

        // Don't save empty string history
        if content.isOnlyStringType && content.stringValue.isEmpty { return true }

        // Overwrite same history
        let isOverwriteHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
        let savedID: PasteboardHistory.ID
        if isOverwriteHistory && !allowDuplicateContent {
            if let matchingHistory {
                savedID = matchingHistory.id
            } else if pasteboardHistoryRepository.fetchHistory(id: historyID) == nil {
                savedID = historyID
            } else {
                // Editing preserves identity, so the original hash may now identify different content.
                savedID = PasteboardHistory.ID(rawValue: UUID().uuidString)
            }
        } else {
            savedID = PasteboardHistory.ID(rawValue: UUID().uuidString)
        }

        let unixTime = Int(Date().timeIntervalSince1970)
        guard let capturedID = pasteboardHistoryRepository.saveCapturedHistory(
            preferredID: savedID, content: content, updateAt: unixTime
        ) else { return false }
        pasteboardHistoryRepository.pruneHistories(settings: HistoryRetentionSettings.current())
        pasteboardHistoryOCRIndexer.enqueueIndexing(historyID: capturedID)
        return true
    }
}

#if DEBUG
extension ClipService {
    func setStoreTypesForTesting(_ storeTypes: [String: NSNumber]) {
        self.storeTypes = storeTypes
    }

    @discardableResult
    func createForTesting(from pasteboard: NSPasteboard) -> Bool {
        create(from: pasteboard)
    }

    func consumeIgnoredPasteboardChangeForTesting(_ changeCount: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ignoredPasteboardChangeCounts.remove(changeCount) != nil
    }
}
#endif
