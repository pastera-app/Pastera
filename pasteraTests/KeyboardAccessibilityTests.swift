//
//  KeyboardAccessibilityTests.swift
//
//  Pastera
//

import AppKit
import Combine
import Dependencies
import KeyHolder
import Testing
@testable import Pastera

extension KeyboardAccessibilityTests {
    @Test
    func masterPasswordSheetUsesThreeSecureFieldsPermanentRecoveryWarningAndCompactLayout() throws {
        let controller = PasswordVaultMasterPasswordSheetController { _, _, completion in
            completion(.success(PasswordVaultMasterPasswordChangeResult(warnings: [])))
        }
        let window = try #require(controller.window)

        #expect(controller.secureFieldCountForTesting == 3)
        #expect(controller.visiblePasswordFieldCountForTesting == 0)
        #expect(controller.fieldLabelsForTesting == [
            pasteraPreferenceString("Current Master Password"),
            pasteraPreferenceString("New Master Password"),
            pasteraPreferenceString("Confirm New Master Password")
        ])
        #expect(controller.recoveryWarningForTesting == pasteraPreferenceString(
            "The new master password encrypts your password vault. If forgotten, it cannot be recovered by any other means."
        ))
        #expect(controller.keyViewOrderForTesting == [
            "masterPassword.current",
            "masterPassword.new",
            "masterPassword.confirmation",
            "masterPassword.cancel",
            "masterPassword.submit"
        ])

        window.setContentSize(NSSize(width: 360, height: window.contentLayoutRect.height))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(controller.controlsFitBoundsForTesting)
    }

    @Test
    func masterPasswordSheetValidatesConfirmationAndVisibilityTogglePreservesValueAndFocus() throws {
        var submissionCount = 0
        let controller = PasswordVaultMasterPasswordSheetController { _, _, _ in
            submissionCount += 1
        }
        let window = try #require(controller.window)
        controller.setValuesForTesting(current: "current", new: "new-password", confirmation: "different")

        controller.submitForTesting()
        #expect(submissionCount == 0)
        #expect(!controller.confirmationErrorForTesting.isEmpty)
        #expect(!controller.primaryButtonEnabledForTesting)

        controller.setValuesForTesting(current: "current", new: "new-password", confirmation: "new-password")
        #expect(controller.primaryButtonEnabledForTesting)
        controller.focusFieldForTesting(index: 1)
        let focusedIdentifier = controller.focusedFieldIdentifierForTesting
        controller.toggleVisibilityForTesting(index: 1)

        #expect(controller.valuesForTesting.new == "new-password")
        #expect(controller.passwordIsVisibleForTesting(index: 1))
        #expect(controller.focusedFieldIdentifierForTesting == focusedIdentifier)
        #expect(window.firstResponder != nil)
    }

    @Test
    func wrongCurrentMasterPasswordClearsOnlyCurrentFieldAndRestoresFocus() {
        let controller = PasswordVaultMasterPasswordSheetController { _, _, completion in
            completion(.failure(.wrongMasterPassword))
        }
        controller.setValuesForTesting(current: "wrong", new: "new-password", confirmation: "new-password")

        controller.submitForTesting()

        #expect(controller.valuesForTesting.current.isEmpty)
        #expect(controller.valuesForTesting.new == "new-password")
        #expect(controller.valuesForTesting.confirmation == "new-password")
        #expect(!controller.currentPasswordErrorForTesting.isEmpty)
        #expect(controller.focusedFieldIdentifierForTesting == "masterPassword.current")
        #expect(!controller.isBusyForTesting)
    }

    @Test
    func masterPasswordSheetBusyStatePreventsDuplicateSubmitAndEscapeUntilSuccess() {
        var submissionCount = 0
        var pendingCompletion: ((Result<PasswordVaultMasterPasswordChangeResult, PasswordVaultError>) -> Void)?
        var successResult: PasswordVaultMasterPasswordChangeResult?
        let controller = PasswordVaultMasterPasswordSheetController(
            changePassword: { _, _, completion in
                submissionCount += 1
                pendingCompletion = completion
            },
            onSuccess: { successResult = $0 }
        )
        controller.setValuesForTesting(current: "current", new: "new-password", confirmation: "new-password")

        controller.submitForTesting()
        controller.submitForTesting()
        controller.cancelForTesting()

        #expect(submissionCount == 1)
        #expect(controller.isBusyForTesting)
        #expect(controller.allInteractiveControlsDisabledForTesting)
        #expect(!controller.didCancelForTesting)

        pendingCompletion?(.success(PasswordVaultMasterPasswordChangeResult(warnings: [.quickUnlockDisabled])))

        #expect(successResult?.warnings == [.quickUnlockDisabled])
        #expect(controller.valuesForTesting.current.isEmpty)
        #expect(controller.valuesForTesting.new.isEmpty)
        #expect(controller.valuesForTesting.confirmation.isEmpty)
    }

}

extension KeyboardAccessibilityTests {
    @Test
    func pasteCommandSendsBalancedCommandTransitionsForRemoteKeyForwarding() throws {
        var events = [CGEvent]()
        var locations = [CGEventTapLocation]()
        PasteService.postPasteCommand { event, location in
            events.append(event)
            locations.append(location)
        }

        // Remote key forwarders track modifiers through flagsChanged, rather
        // than interpreting the modifier flags attached to a V key event.
        var commandIsDown = false
        var commandWasDownForKeyDown = [Bool]()
        for event in events {
            if event.type == .flagsChanged,
               event.getIntegerValueField(.keyboardEventKeycode) == 55 {
                commandIsDown = event.flags.contains(.maskCommand)
            } else if event.type == .keyDown {
                commandWasDownForKeyDown.append(commandIsDown)
            }
        }
        #expect(commandWasDownForKeyDown == [true])
        #expect(!commandIsDown, "Command must be released after pasting")
        #expect(events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(locations.allSatisfy { $0 == .cgAnnotatedSessionEventTap })

        try #require(events.count == 4)
        #expect(events[0].getIntegerValueField(.keyboardEventKeycode) == 55)
        #expect(events[3].getIntegerValueField(.keyboardEventKeycode) == 55)
        #expect(events[1].getIntegerValueField(.keyboardEventKeycode) ==
                events[2].getIntegerValueField(.keyboardEventKeycode))
        #expect(events[0].flags == .maskCommand)
        #expect(events[1].flags == .maskCommand)
        #expect(events[2].flags == .maskCommand)
        #expect(events[3].flags.isEmpty)
    }

}

@MainActor
@Suite(.serialized)
struct KeyboardAccessibilityTests {

    @Test
    func pasteShortcutResolverUsesCurrentLayoutMapping() {
        let resolver = PasteShortcutKeyCodeResolver { keyCode, _ in
            keyCode == 42 ? "v" : nil
        }

        #expect(resolver.keyCode(for: "v", carbonModifiers: 0) == 42)
    }

    @Test
    func pasteShortcutResolverFallsBackToAnsiVWhenLayoutCannotBeRead() {
        let resolver = PasteShortcutKeyCodeResolver { _, _ in nil }

        #expect(resolver.keyCode(for: "v", carbonModifiers: 0) == 9)
    }

    private func makePreferencesController() -> CPYPreferencesWindowController {
        CPYPreferencesWindowController(
            frameAutosaveName: "KeyboardAccessibilityTests.\(UUID().uuidString)"
        )
    }

    @Test
    func shortcutRecordViewsUseDarkElevatedBackgroundInsteadOfWhite() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        controller.window?.appearance = darkAppearance
        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "Shortcuts")

        let brightnessValues = controller.preferenceRecordViewBackgroundBrightnessValuesForTesting

        #expect(brightnessValues.count >= 4)
        for brightness in brightnessValues {
            #expect(brightness < 0.40, "RecordView should not keep a white background in dark mode")
        }
    }

    @Test
    func preferencePanesUseComfortableVerticalRhythm() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)

        for paneTitle in ["General", "History & Preview", "Shortcuts", "About Pastera"] {
            controller.showPreferencePaneForTesting(title: paneTitle)
            let minimumGap = try #require(task3PreferenceMinimumVerticalGap(controller, paneTitle: paneTitle))
            #expect(minimumGap >= 8, "\(paneTitle) pane controls are visually cramped: \(minimumGap)")
        }
    }

    @Test
    func preferenceSidebarCanSwitchPanesWithKeyboard() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "General")

        let downEvent = try makeKeyEvent(keyCode: 125, characters: "\u{F701}")
        let returnEvent = try makeKeyEvent(keyCode: 36, characters: "\r")

        #expect(controller.handlePreferenceKeyboardEventForTesting(downEvent))
        #expect(controller.selectedPreferencePaneTitleForTesting == "History & Preview")

        #expect(controller.handlePreferenceKeyboardEventForTesting(returnEvent))
        #expect(controller.focusedPreferencePaneControlTitleForTesting != nil)
    }

    @Test
    func preferenceWindowDefaultsKeyboardFocusToSelectedSidebar() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)

        let downEvent = try makeKeyEvent(keyCode: 125, characters: "\u{F701}")

        #expect(controller.focusedPreferenceSidebarTitleForTesting == "General")
        #expect(controller.handlePreferenceKeyboardEventForTesting(downEvent))
        #expect(controller.focusedPreferenceSidebarTitleForTesting == "History & Preview")
        #expect(controller.selectedPreferencePaneTitleForTesting == "History & Preview")
    }

    @Test
    func preferenceSidebarTabSwitchesToNextSidebarPane() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "General")

        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")

        #expect(controller.handlePreferenceKeyboardEventForTesting(tabEvent))
        #expect(controller.focusedPreferenceSidebarTitleForTesting == "History & Preview")
        #expect(controller.selectedPreferencePaneTitleForTesting == "History & Preview")
    }

    @Test
    func preferencePaneSwitchingKeepsWindowSizeStableAndUsesScrollDocuments() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        let initialFrameSize = try #require(controller.window?.frame.size)

        #expect(initialFrameSize == NSSize(width: 760, height: 600))
        #expect(controller.window?.minSize == NSSize(width: 680, height: 480))

        for paneTitle in ["General", "History & Preview", "Excluded Apps", "Shortcuts", "About Pastera"] {
            controller.showPreferencePaneForTesting(title: paneTitle)

            #expect(controller.window?.frame.size == initialFrameSize)
            #expect(controller.preferencePaneUsesScrollDocumentForTesting)
            if paneTitle == "General" {
                #expect(controller.selectedPaneDocumentOriginForTesting.x == 16)
                #expect(controller.selectedPaneDocumentOriginForTesting.y >= 16)
            } else {
                #expect(
                    controller.selectedPaneDocumentOriginForTesting == NSPoint(x: 16, y: 16),
                    "\(paneTitle) pane should be pinned to the top-leading inset"
                )
                let visibleTopGap = try #require(controller.preferencePaneVisibleTopGapForTesting)
                #expect(
                    visibleTopGap <= 28,
                    "\(paneTitle) pane content starts too low: \(visibleTopGap)"
                )
            }
            #expect(controller.selectedPaneDocumentWidthForTesting <= controller.preferencePaneViewportWidthForTesting)
        }
    }

    @Test
    func preferenceWindowUsesCompactSidebarAndWidePaneContent() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "History & Preview")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let sidebarView = try #require(preferenceSidebarView(in: contentView))

        #expect(sidebarView.frame.width == 188)
        #expect(controller.selectedPaneDocumentWidthForTesting >= controller.preferencePaneViewportWidthForTesting - 40)

        #expect(
            controller.selectedPaneDocumentOriginForTesting.y == 16,
            "History & Preview pane should start at the top inset"
        )
    }

    @Test
    func typePreferenceCheckboxesAreNotClippedByTheirContainers() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "History & Preview")

        let contentView = try #require(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()
        let savedTypeIdentifiers = Set(PasteboardAvailableType.allCases.map(\.rawValue))
        let previewTypeIdentifiers = Set(PasteraFilePreviewKind.allCases.map(\.rawValue))
        let buttons = preferenceButtons(in: contentView)
        let savedTypeButtons = buttons.filter {
            $0.identifier.map { savedTypeIdentifiers.contains($0.rawValue) } == true
        }
        let previewTypeButtons = buttons.filter {
            $0.identifier.map { previewTypeIdentifiers.contains($0.rawValue) } == true
        }

        #expect(savedTypeButtons.count == 7)
        #expect(previewTypeButtons.count == 5)
        #expect(Set(savedTypeButtons.compactMap { $0.identifier?.rawValue }) == savedTypeIdentifiers)
        #expect(Set(previewTypeButtons.compactMap { $0.identifier?.rawValue }) == previewTypeIdentifiers)
        #expect((savedTypeButtons + previewTypeButtons).allSatisfy { $0.title.isEmpty })
        #expect((savedTypeButtons + previewTypeButtons).allSatisfy {
            $0.accessibilityLabel()?.isEmpty == false
        })

        for button in savedTypeButtons + previewTypeButtons {
            let identifier = button.identifier?.rawValue ?? "missing identifier"
            let containerBounds = try #require(button.superview?.bounds)
            #expect(button.frame.minX >= 0, "\(identifier) is clipped on the leading edge")
            #expect(button.frame.maxX <= containerBounds.width, "\(identifier) exceeds its container width")
            #expect(button.frame.minY >= 0, "\(identifier) is clipped on the top/bottom edge")
            #expect(button.frame.maxY <= containerBounds.height, "\(identifier) exceeds its container height")
        }
    }

    @Test
    func typePreferenceCheckboxCanBeToggledFromKeyboard() throws {
        let defaults = AppEnvironment.current.defaults
        let originalStoreTypes = defaults.object(forKey: Constants.UserDefaults.storeTypes)
        let stringIdentifier = PasteboardAvailableType.string.rawValue
        var initialStoreTypes = PasteboardAvailableType.allCases.reduce(into: [String: NSNumber]()) {
            $0[$1.rawValue] = NSNumber(value: true)
        }
        initialStoreTypes[stringIdentifier] = NSNumber(value: false)
        defaults.set(initialStoreTypes, forKey: Constants.UserDefaults.storeTypes)
        defer {
            if let originalStoreTypes {
                defaults.set(originalStoreTypes, forKey: Constants.UserDefaults.storeTypes)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.storeTypes)
            }
        }

        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "History & Preview")
        let spaceEvent = try makeKeyEvent(keyCode: 49, characters: " ")

        let contentView = try #require(controller.window?.contentView)
        let plainTextButton = try #require(preferenceButtons(in: contentView).first {
            $0.identifier?.rawValue == stringIdentifier
        })
        #expect(plainTextButton.title.isEmpty)
        #expect(plainTextButton.accessibilityLabel() == pasteraPreferenceString("Plain Text"))
        #expect(controller.window?.makeFirstResponder(plainTextButton) == true)
        #expect(controller.window?.firstResponder === plainTextButton)
        #expect(controller.focusedPreferencePaneControlTitleForTesting == pasteraPreferenceString("Plain Text"))
        #expect(plainTextButton.state == .off)

        #expect(controller.handlePreferenceKeyboardEventForTesting(spaceEvent))
        #expect(plainTextButton.state == .on)
        let persistedStoreTypes = try #require(
            defaults.dictionary(forKey: Constants.UserDefaults.storeTypes)
        )
        #expect((persistedStoreTypes[stringIdentifier] as? NSNumber)?.boolValue == true)
    }

    @Test
    func preferenceCompactMenuPaneFitsInsideFixedWindow() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.showPreferencePaneForTesting(title: "General")

        let initialFrameSize = try #require(controller.window?.frame.size)

        #expect(controller.preferencePaneUsesScrollDocumentForTesting)
        #expect(controller.selectedPaneDocumentHeightForTesting <= controller.preferencePaneViewportHeightForTesting + 0.5)
        #expect(controller.window?.frame.size == initialFrameSize)
    }

    @Test
    func softwareUpdateSidebarParticipatesInTabAndShiftTabNavigation() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "Software Update")

        #expect(
            controller.cachedPreferencePageForTesting(paneID: .softwareUpdate)
                is CPYSoftwareUpdatePreferenceViewController
        )

        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")
        let shiftTabEvent = try makeKeyEvent(keyCode: 48, characters: "\t", modifierFlags: [.shift])

        #expect(controller.handlePreferenceKeyboardEventForTesting(tabEvent))
        #expect(controller.focusedPreferenceSidebarTitleForTesting == "About Pastera")
        #expect(controller.selectedPreferencePaneTitleForTesting == "About Pastera")

        #expect(controller.handlePreferenceKeyboardEventForTesting(shiftTabEvent))
        #expect(controller.focusedPreferenceSidebarTitleForTesting == "Software Update")
        #expect(controller.selectedPreferencePaneTitleForTesting == "Software Update")
    }

    @Test
    func preferencePaneArrowKeysMoveBetweenFocusableControls() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "General")

        let returnEvent = try makeKeyEvent(keyCode: 36, characters: "\r")
        let downEvent = try makeKeyEvent(keyCode: 125, characters: "\u{F701}")

        #expect(controller.handlePreferenceKeyboardEventForTesting(returnEvent))
        let firstControl = try #require(controller.window?.firstResponder as? NSView)
        #expect(
            controller.focusedPreferencePaneControlTitleForTesting
                == pasteraPreferenceString("Launch on Login")
        )

        #expect(controller.handlePreferenceKeyboardEventForTesting(downEvent))
        let secondControl = try #require(controller.window?.firstResponder as? NSView)
        #expect(secondControl !== firstControl)
        #expect(controller.focusedPreferencePaneControlTitleForTesting == "Slider")
    }

    @Test
    func preferenceRecordViewEventsAreNotInterceptedByWindowCommands() throws {
        let controller = makePreferencesController()
        defer { controller.close() }

        controller.showWindow(nil)
        controller.focusPreferenceSidebarForTesting(title: "Shortcuts")

        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")
        let commandFEvent = try makeKeyEvent(keyCode: 3, characters: "f", modifierFlags: [.command])

        let contentView = try #require(controller.window?.contentView)
        let recordView = try #require(preferenceRecordViews(in: contentView).first)
        #expect(controller.window?.makeFirstResponder(recordView) == true)

        #expect(!controller.handlePreferenceKeyboardEventForTesting(tabEvent))
        #expect(controller.window?.firstResponder === recordView)
        #expect(!controller.handlePreferenceKeyboardEventForTesting(commandFEvent))
        #expect(controller.window?.firstResponder === recordView)
    }

    @Test
    func snippetEditorToolbarButtonsCanBeConfirmedFromKeyboard() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folder = SnippetFolder(id: folderID, title: "untitled folder", index: 0, isEnabled: true)
        var didInsertFolder = false
        let spaceEvent = try makeKeyEvent(keyCode: 49, characters: " ")

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(
                details: [],
                insertedFolder: folder,
                onInsertFolder: { didInsertFolder = true }
            )
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.focusToolbarButtonForTesting(title: "Add Folder")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(spaceEvent))
            #expect(didInsertFolder)
        }
    }

    @Test
    func snippetEditorOutlineSupportsKeyboardRenameToggleAndDelete() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "test1",
                    content: "value",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        var toggledSnippetID: Snippet.ID?
        var deletedSnippetID: Snippet.ID?
        let returnEvent = try makeKeyEvent(keyCode: 36, characters: "\r")
        let spaceEvent = try makeKeyEvent(keyCode: 49, characters: " ")
        let deleteEvent = try makeKeyEvent(keyCode: 51, characters: "\u{7F}")

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(
                details: [detail],
                onUpdateSnippetEnabled: { id, _ in toggledSnippetID = id },
                onDeleteSnippet: { id in deletedSnippetID = id }
            )
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.selectSnippetForTesting(id: snippetID)

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(returnEvent))
            #expect(controller.isEditingOutlineTitleForTesting)

            controller.cancelOutlineEditingForTesting()
            #expect(controller.handleSnippetEditorKeyboardEventForTesting(spaceEvent))
            #expect(toggledSnippetID == snippetID)

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(deleteEvent))
            #expect(deletedSnippetID == snippetID)
        }
    }

    @Test
    func snippetEditorTabCyclesThroughToolbarOutlineAndDetail() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "test1",
                    content: "value",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")
        let shiftTabEvent = try makeKeyEvent(keyCode: 48, characters: "\t", modifierFlags: [.shift])

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(details: [detail])
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.focusToolbarButtonForTesting(title: "Export")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(tabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "outline")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(tabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "detail")

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(shiftTabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "outline")
        }
    }

    @Test
    func snippetEditorTextViewTabMovesFocusAndOptionTabKeepsTextInput() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "test1",
                    content: "value",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        let tabEvent = try makeKeyEvent(keyCode: 48, characters: "\t")
        let optionTabEvent = try makeKeyEvent(keyCode: 48, characters: "\t", modifierFlags: [.option])

        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(details: [detail])
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.selectSnippetForTesting(id: snippetID)
            controller.focusSnippetTextEditorForTesting()

            #expect(!controller.handleSnippetEditorKeyboardEventForTesting(optionTabEvent))

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(tabEvent))
            #expect(controller.focusedSnippetEditorAreaForTesting == "toolbar")
        }
    }

    @Test
    func snippetEditorToolbarIsHostedInScrollContainer() {
        withDependencies {
            $0.snippetRepository = SnippetEditorKeyboardRepository(details: [])
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)

            #expect(controller.toolbarUsesScrollContainerForTesting)
        }
    }
}

private extension KeyboardAccessibilityTests {
    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func preferenceButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        view.subviews.forEach { buttons.append(contentsOf: preferenceButtons(in: $0)) }
        return buttons
    }

    private func preferenceRecordViews(in view: NSView) -> [RecordView] {
        var recordViews = view.subviews.compactMap { $0 as? RecordView }
        view.subviews.forEach { recordViews.append(contentsOf: preferenceRecordViews(in: $0)) }
        return recordViews
    }

    private func preferenceSidebarView(in contentView: NSView) -> NSView? {
        contentView.subviews
            .filter { $0.frame.minX <= 0.5 && $0.frame.height >= contentView.bounds.height - 1 }
            .sorted { $0.frame.width < $1.frame.width }
            .first
    }

}

@MainActor
private func task3PreferenceMinimumVerticalGap(
    _ controller: CPYPreferencesWindowController,
    paneTitle: String
) -> CGFloat? {
    let paneID: PasteraPreferencePaneID?
    switch paneTitle {
    case "General": paneID = .general
    case "History & Preview": paneID = .history
    case "Shortcuts": paneID = .shortcuts
    case "About Pastera": paneID = .about
    default: paneID = nil
    }
    guard let paneID,
          let nativePage = controller.cachedPreferencePageForTesting(paneID: paneID)
            as? PasteraPreferencePageViewController else {
        return controller.minimumVisibleControlVerticalGapForTesting
    }
    return task3MinimumNativePreferenceGroupGap(in: nativePage.view)
}

func task3MinimumNativePreferenceGroupGap(in rootView: NSView) -> CGFloat? {
    let frames = task3PreferenceGroups(in: rootView)
        .map { rootView.convert($0.bounds, from: $0) }
        .sorted { $0.minY < $1.minY }
    guard frames.count > 1 else { return nil }
    return zip(frames, frames.dropFirst()).map { $1.minY - $0.maxY }.min()
}

private func task3PreferenceGroups(in view: NSView) -> [PasteraPreferenceGroupView] {
    view.subviews.flatMap { subview in
        if let group = subview as? PasteraPreferenceGroupView { return [group] }
        return task3PreferenceGroups(in: subview)
    }
}

private struct SnippetEditorKeyboardRepository: SnippetRepositoryProtocol {
    var details: [SnippetFolderDetail]
    var insertedFolder: SnippetFolder?
    var onInsertFolder: () -> Void = {}
    var onUpdateSnippetEnabled: (Snippet.ID, Bool) -> Void = { _, _ in }
    var onDeleteSnippet: (Snippet.ID) -> Void = { _ in }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just(details).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { details }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { details.first { $0.folder.id == id } }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? {
        onInsertFolder()
        return insertedFolder
    }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func removeDuplicateFoldersAndSnippets() -> Int { 0 }
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool { true }
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? {
        details.flatMap(\.snippets).first { $0.id == id }
    }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool { true }
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {
        onUpdateSnippetEnabled(id, isEnabled)
    }
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {
        onDeleteSnippet(id)
    }
}
