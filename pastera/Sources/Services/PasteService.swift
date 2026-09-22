//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Carbon
import Dependencies
import Foundation

struct PasteShortcutKeyCodeResolver {
    typealias CharacterProvider = (_ keyCode: CGKeyCode, _ carbonModifiers: Int) -> String?

    private let characterProvider: CharacterProvider

    init(characterProvider: @escaping CharacterProvider = Self.currentKeyboardCharacter) {
        self.characterProvider = characterProvider
    }

    func keyCode(for character: Character, carbonModifiers: Int) -> CGKeyCode {
        let expectedCharacter = String(character).lowercased()
        for keyCode in CGKeyCode(0)..<CGKeyCode(128) {
            if characterProvider(keyCode, carbonModifiers)?.lowercased() == expectedCharacter {
                return keyCode
            }
        }
        return CGKeyCode(kVK_ANSI_V)
    }

    private static func currentKeyboardCharacter(keyCode: CGKeyCode, carbonModifiers: Int) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let modifierState = UInt32((carbonModifiers >> 8) & 0xff)
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var characterCount = 0
        let status = layoutData.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &characterCount,
                &characters
            )
        }
        guard status == noErr else { return nil }
        return String(utf16CodeUnits: characters, count: characterCount)
    }
}

struct PasteTargetContext {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let application: NSRunningApplication?
    let focusedElement: AXUIElement?

    static func capture() -> PasteTargetContext? {
        capture(from: NSWorkspace.shared.frontmostApplication)
    }

    static func capture(from application: NSRunningApplication?) -> PasteTargetContext? {
        guard let application else { return nil }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }

        return PasteTargetContext(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            application: application,
            focusedElement: focusedElement(for: application.processIdentifier)
        )
    }

    private static func focusedElement(for processIdentifier: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

struct PasteboardHistorySelectionRequest {
    let id: PasteboardHistory.ID
    let targetContext: PasteTargetContext?
}

struct SnippetSelectionRequest {
    let id: Snippet.ID
    let targetContext: PasteTargetContext?
}

final class PasteService {
    private enum RestoreMetrics {
        static let interval: TimeInterval = 0.02
        static let focusSettleDelay: TimeInterval = 0.04
        static let maxAttempts = 12
    }

    // MARK: - Properties
    fileprivate let lock = NSRecursiveLock(name: "com.pastera-app.Pastera.Pastable")

    @Dependency(\.pasteboardHistoryRepository)
    private var pasteboardHistoryRepository

    var inputPasteCommandEnabledProvider: () -> Bool
    var accessibilityEnabledProvider: () -> Bool
    var accessibilityAlertPresenter: () -> Void
    var frontmostProcessIdentifierProvider: () -> pid_t?
    var targetApplicationActivator: (PasteTargetContext) -> Void
    var focusedElementRestorer: (PasteTargetContext) -> Void
    var pasteCommandSender: () -> Void
    var secureEventInputEnabledProvider: () -> Bool
    var textInputSender: (String) -> Void
    var scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
    var clipboardScriptCoordinatorProvider: () -> ClipboardScriptCoordinating?
    var pasteboardProvider: () -> NSPasteboard

    init(
        inputPasteCommandEnabledProvider: @escaping () -> Bool = {
            AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand)
        },
        accessibilityEnabledProvider: @escaping () -> Bool = {
            AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false)
        },
        accessibilityAlertPresenter: @escaping () -> Void = {
            AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
        },
        frontmostProcessIdentifierProvider: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        targetApplicationActivator: @escaping (PasteTargetContext) -> Void = { context in
            PasteService.activateTargetApplication(for: context)
        },
        focusedElementRestorer: @escaping (PasteTargetContext) -> Void = { context in
            PasteService.restoreFocusedElement(for: context)
        },
        pasteCommandSender: @escaping () -> Void = {
            PasteService.postPasteCommand()
        },
        secureEventInputEnabledProvider: @escaping () -> Bool = {
            IsSecureEventInputEnabled()
        },
        textInputSender: @escaping (String) -> Void = { text in
            PasteService.postTextInput(text)
        },
        clipboardScriptCoordinatorProvider: @escaping () -> ClipboardScriptCoordinating? = { nil },
        pasteboardProvider: @escaping () -> NSPasteboard = { .general },
        scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.inputPasteCommandEnabledProvider = inputPasteCommandEnabledProvider
        self.accessibilityEnabledProvider = accessibilityEnabledProvider
        self.accessibilityAlertPresenter = accessibilityAlertPresenter
        self.frontmostProcessIdentifierProvider = frontmostProcessIdentifierProvider
        self.targetApplicationActivator = targetApplicationActivator
        self.focusedElementRestorer = focusedElementRestorer
        self.pasteCommandSender = pasteCommandSender
        self.secureEventInputEnabledProvider = secureEventInputEnabledProvider
        self.textInputSender = textInputSender
        self.clipboardScriptCoordinatorProvider = clipboardScriptCoordinatorProvider
        self.pasteboardProvider = pasteboardProvider
        self.scheduleAfter = scheduleAfter
    }

}

// MARK: - Copy
extension PasteService {
    func paste(with history: PasteboardHistory) {
        paste(with: history, restoring: nil)
    }

    func paste(with history: PasteboardHistory, restoring targetContext: PasteTargetContext?) {
        guard let content = pasteboardHistoryRepository.fetchContent(id: history.id) else { return }

        if content.isOnlyStringType {
            pasteText(content.stringValue, restoring: targetContext)
            return
        }
        copyToPasteboard(with: content)
        paste(restoring: targetContext)
    }

    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = pasteboardProvider()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(string, forType: .string)
    }

    private func copyToPasteboard(with content: PasteboardContent) {
        copyContentToPasteboard(content, to: pasteboardProvider())
    }

    func copyContentToPasteboard(_ content: PasteboardContent, to pasteboard: NSPasteboard) {
        lock.lock(); defer { lock.unlock() }

        let items = pasteboardItems(for: content)
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    private func pasteboardItems(for content: PasteboardContent) -> [NSPasteboardItem] {
        var countsByType: [NSPasteboard.PasteboardType: Int] = [:]
        var generalItems = [NSPasteboardItem]()
        var items = [NSPasteboardItem]()

        for asset in content.assets {
            if asset.type.isClipyImageType {
                let item = NSPasteboardItem()
                setImageAsset(asset, on: item)
                items.append(item)
            } else {
                let index = countsByType[asset.type] ?? 0
                countsByType[asset.type] = index + 1
                if !generalItems.indices.contains(index) {
                    let item = NSPasteboardItem()
                    generalItems.append(item)
                    items.append(item)
                }
                generalItems[index].setData(asset.data, forType: asset.type)
            }
        }

        return items
    }

    private func setImageAsset(_ asset: PasteboardContent.Asset, on item: NSPasteboardItem) {
        switch asset.type {
        case .clipySnipastePNG:
            item.setData(asset.data, forType: asset.type)
            item.setData(asset.data, forType: .png)
        case .clipyApplePNG:
            item.setData(asset.data, forType: .png)
        case .deprecatedTIFF:
            item.setData(asset.data, forType: .tiff)
        default:
            item.setData(asset.data, forType: asset.type)
            guard asset.type != .png, asset.type != .tiff,
                  let image = NSImage(data: asset.data),
                  let pngData = PasteraImageEncoding.pngData(from: image)
            else {
                return
            }
            item.setData(pngData, forType: .png)
        }
    }
}

// MARK: - Paste
extension PasteService {
    func paste() {
        paste(restoring: nil)
    }

    func paste(restoring targetContext: PasteTargetContext?) {
        paste(restoring: targetContext) { [weak self] in
            self?.pasteCommandSender()
        }
    }

    func pasteText(_ text: String, restoring targetContext: PasteTargetContext?) {
        guard let coordinator = clipboardScriptCoordinatorProvider(),
              coordinator.hasEnabledScripts(for: .paste)
        else {
            pasteResolvedText(text, restoring: targetContext)
            return
        }

        Task { [weak self] in
            let outcome = await coordinator.transform(
                text: text,
                sourceAppBundleIdentifier: targetContext?.bundleIdentifier,
                trigger: .paste
            )
            let resolvedText: String
            if case let .transformed(output) = outcome {
                resolvedText = output
            } else {
                resolvedText = text
            }
            await MainActor.run {
                self?.pasteResolvedText(resolvedText, restoring: targetContext)
            }
        }
    }

    /// Pastes text that has already been resolved by an explicitly selected script.
    /// This deliberately bypasses the automatic `.paste` pipeline so the selected
    /// script is never followed by a second transform.
    func pasteResolvedScriptText(_ text: String, restoring targetContext: PasteTargetContext?) {
        pasteResolvedText(text, restoring: targetContext)
    }

    private func pasteResolvedText(_ text: String, restoring targetContext: PasteTargetContext?) {
        copyToPasteboard(with: text)
        paste(restoring: targetContext) { [weak self] in
            guard let self else { return }
            if self.secureEventInputEnabledProvider() {
                self.textInputSender(text)
            } else {
                self.pasteCommandSender()
            }
        }
    }

    private func paste(restoring targetContext: PasteTargetContext?, sendPaste: @escaping () -> Void) {
        guard inputPasteCommandEnabledProvider() else { return }
        // Check Accessibility Permission
        guard accessibilityEnabledProvider() else {
            accessibilityAlertPresenter()
            return
        }

        guard let targetContext else {
            scheduleAfter(0) { [weak self] in
                guard self != nil else { return }
                sendPaste()
            }
            return
        }

        targetApplicationActivator(targetContext)
        waitForTargetAndPaste(targetContext, attempt: 0, sendPaste: sendPaste)
    }

    private func waitForTargetAndPaste(
        _ targetContext: PasteTargetContext,
        attempt: Int,
        sendPaste: @escaping () -> Void
    ) {
        if frontmostProcessIdentifierProvider() == targetContext.processIdentifier || attempt >= RestoreMetrics.maxAttempts {
            restoreFocusThenPaste(targetContext, sendPaste: sendPaste)
            return
        }

        scheduleAfter(RestoreMetrics.interval) { [weak self] in
            self?.waitForTargetAndPaste(targetContext, attempt: attempt + 1, sendPaste: sendPaste)
        }
    }

    private func restoreFocusThenPaste(_ targetContext: PasteTargetContext, sendPaste: @escaping () -> Void) {
        focusedElementRestorer(targetContext)
        scheduleAfter(RestoreMetrics.focusSettleDelay) { [weak self] in
            guard self != nil else { return }
            sendPaste()
        }
    }

    private static func activateTargetApplication(for context: PasteTargetContext) {
        guard let application = context.application ?? NSRunningApplication(processIdentifier: context.processIdentifier) else {
            return
        }
        guard !application.isTerminated else { return }
        application.activate(options: [.activateIgnoringOtherApps])
    }

    private static func restoreFocusedElement(for context: PasteTargetContext) {
        guard let focusedElement = context.focusedElement else { return }
        AXUIElementSetAttributeValue(focusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    static func postPasteCommand(postEvent: (CGEvent, CGEventTapLocation) -> Void = { event, location in
        event.post(tap: location)
    }) {
        let vKeyCode = PasteShortcutKeyCodeResolver().keyCode(for: "v", carbonModifiers: cmdKey)
        let source = CGEventSource(stateID: .combinedSessionState)
        // Disable local keyboard events while pasting
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
              let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else {
            return
        }

        // Remote key forwarders need Command's flagsChanged events; flags on V
        // alone can arrive as a plain "v". Construct the release before posting.
        commandDown.flags = .maskCommand
        keyVDown.flags = .maskCommand
        keyVUp.flags = .maskCommand
        commandUp.flags = []
        for event in [commandDown, keyVDown, keyVUp, commandUp] {
            postEvent(event, .cgAnnotatedSessionEventTap)
        }
    }

    private static func postTextInput(_ text: String) {
        guard !text.isEmpty else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        for character in text {
            let utf16 = Array(String(character).utf16)
            utf16.withUnsafeBufferPointer { buffer in
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buffer.baseAddress)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buffer.baseAddress)
                keyDown?.post(tap: .cgAnnotatedSessionEventTap)
                keyUp?.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }
}
