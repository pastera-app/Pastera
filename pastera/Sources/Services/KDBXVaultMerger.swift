import Foundation
import KDBXKit

struct KDBXVaultMergeResult {
    let content: KDBXContent
    let conflictCopyCount: Int
    var hasConflictCopies: Bool { conflictCopyCount > 0 }
}

final class KDBXVaultMerger {
    func merge(local: KDBXContent, remote: KDBXContent) -> KDBXVaultMergeResult {
        var output = remote
        var conflictCopyCount = 0
        output.database.root.group = mergeGroup(
            local.database.root.group,
            remote.database.root.group,
            conflictCopyCount: &conflictCopyCount
        )
        let tombstones = (local.database.root.deletedObjects + remote.database.root.deletedObjects).reduce(
            into: [UUID: KDBX.DeletedObject]()
        ) {
            if ($0[$1.uuid]?.deletionTime ?? .distantPast) < $1.deletionTime { $0[$1.uuid] = $1 }
        }
        output.database.root.deletedObjects = Array(tombstones.values)
        removeDeleted(from: &output.database.root.group, tombstones: tombstones)
        return KDBXVaultMergeResult(content: output, conflictCopyCount: conflictCopyCount)
    }

    private func mergeGroup(
        _ local: KDBX.Group,
        _ remote: KDBX.Group,
        conflictCopyCount: inout Int
    ) -> KDBX.Group {
        var output = newer(local, remote)
        let preferredGroupIDs = output.groups.map(\.uuid)
        output.entries = mergeEntries(
            local.entries,
            remote.entries,
            preferredEntryIDs: output.entries.map(\.uuid),
            conflictCopyCount: &conflictCopyCount
        )
        var groups = Dictionary(uniqueKeysWithValues: remote.groups.map { ($0.uuid, $0) })
        for group in local.groups {
            if let remoteGroup = groups[group.uuid] {
                groups[group.uuid] = mergeGroup(group, remoteGroup, conflictCopyCount: &conflictCopyCount)
            } else {
                groups[group.uuid] = group
            }
        }
        output.groups = preferredGroupIDs.compactMap { groups.removeValue(forKey: $0) }
        for group in local.groups + remote.groups {
            if let remaining = groups.removeValue(forKey: group.uuid) {
                output.groups.append(remaining)
            }
        }
        return output
    }

    private func mergeEntries(
        _ local: [KDBX.Entry],
        _ remote: [KDBX.Entry],
        preferredEntryIDs: [UUID],
        conflictCopyCount: inout Int
    ) -> [KDBX.Entry] {
        var entries = Dictionary(uniqueKeysWithValues: remote.map { ($0.uuid, $0) })
        var generatedEntryIDs = [UUID]()
        for entry in local {
            guard let remoteEntry = entries[entry.uuid] else {
                entries[entry.uuid] = entry
                continue
            }
            let localTime = entry.times?.lastModificationTime ?? .distantPast
            let remoteTime = remoteEntry.times?.lastModificationTime ?? .distantPast
            if sameEntryContent(entry, remoteEntry) {
                var current = localTime > remoteTime ? entry : remoteEntry
                current.history = mergedHistory(
                    entry.history + remoteEntry.history,
                    excludingCurrent: current
                )
                entries[entry.uuid] = current
                continue
            }
            if localTime == remoteTime {
                var conflict = entry
                conflict.uuid = UUID()
                setTitle(on: &conflict, title: "\(title(of: entry)) (Conflict)")
                entries[conflict.uuid] = conflict
                generatedEntryIDs.append(conflict.uuid)
                conflictCopyCount += 1
            } else {
                var winner = localTime > remoteTime ? entry : remoteEntry
                var loser = localTime > remoteTime ? remoteEntry : entry
                loser.history = []
                let loserHistory = localTime > remoteTime ? remoteEntry.history : entry.history
                winner.history = mergedHistory(
                    winner.history + loserHistory + [loser],
                    excludingCurrent: winner
                )
                entries[entry.uuid] = winner
            }
        }
        var output = preferredEntryIDs.compactMap { entries.removeValue(forKey: $0) }
        for entry in local + remote {
            if let remaining = entries.removeValue(forKey: entry.uuid) {
                output.append(remaining)
            }
        }
        output.append(contentsOf: generatedEntryIDs.compactMap { entries.removeValue(forKey: $0) })
        output.append(contentsOf: entries.values.sorted { $0.uuid.uuidString < $1.uuid.uuidString })
        return output
    }

    private func mergedHistory(
        _ candidates: [KDBX.Entry],
        excludingCurrent current: KDBX.Entry
    ) -> [KDBX.Entry] {
        var unique = [KDBX.Entry]()
        for candidate in candidates {
            var version = candidate
            version.history = []
            guard !sameHistoryVersion(version, current),
                  !unique.contains(where: { sameHistoryVersion($0, version) }) else { continue }
            unique.append(version)
        }
        let chronological = unique.enumerated().sorted { lhs, rhs in
            let lhsTime = lhs.element.times?.lastModificationTime ?? .distantPast
            let rhsTime = rhs.element.times?.lastModificationTime ?? .distantPast
            return lhsTime == rhsTime ? lhs.offset < rhs.offset : lhsTime < rhsTime
        }.map(\.element)
        return Array(chronological.suffix(10))
    }

    private func sameHistoryVersion(_ lhs: KDBX.Entry, _ rhs: KDBX.Entry) -> Bool {
        lhs.uuid == rhs.uuid &&
            lhs.times?.lastModificationTime == rhs.times?.lastModificationTime &&
            sameEntryContent(lhs, rhs)
    }

    private func sameEntryContent(_ lhs: KDBX.Entry, _ rhs: KDBX.Entry) -> Bool {
        lhs.iconID == rhs.iconID &&
            lhs.customIconUUID == rhs.customIconUUID &&
            lhs.foregroundColor == rhs.foregroundColor &&
            lhs.backgroundColor == rhs.backgroundColor &&
            lhs.overrideURL == rhs.overrideURL &&
            lhs.qualityCheck == rhs.qualityCheck &&
            lhs.tags == rhs.tags &&
            lhs.previousParentGroup == rhs.previousParentGroup &&
            lhs.strings == rhs.strings &&
            lhs.binaries == rhs.binaries &&
            lhs.autoType == rhs.autoType &&
            lhs.customData == rhs.customData
    }

    private func newer(_ local: KDBX.Group, _ remote: KDBX.Group) -> KDBX.Group {
        (local.times?.lastModificationTime ?? .distantPast) >
            (remote.times?.lastModificationTime ?? .distantPast) ? local : remote
    }

    private func removeDeleted(
        from group: inout KDBX.Group,
        tombstones: [UUID: KDBX.DeletedObject]
    ) {
        func isDeleted(_ id: UUID, modifiedAt: Date?) -> Bool {
            guard let deletion = tombstones[id] else { return false }
            let modificationTime = modifiedAt ?? .distantPast
            // KDBXKit rounds persisted dates to whole seconds. Deletion wins ties
            // so stale in-memory objects and encrypted replicas cannot revive them.
            return deletion.deletionTime.timeIntervalSince1970.rounded() >=
                modificationTime.timeIntervalSince1970.rounded()
        }
        group.entries.removeAll { entry in
            isDeleted(entry.uuid, modifiedAt: entry.times?.lastModificationTime)
        }
        group.groups.removeAll { child in
            isDeleted(child.uuid, modifiedAt: child.times?.lastModificationTime)
        }
        for index in group.groups.indices {
            removeDeleted(from: &group.groups[index], tombstones: tombstones)
        }
    }

    private func title(of entry: KDBX.Entry) -> String {
        entry.strings.first(where: { $0.key == "Title" })?.value.revealedString ?? "Password"
    }

    private func setTitle(on entry: inout KDBX.Entry, title: String) {
        if let index = entry.strings.firstIndex(where: { $0.key == "Title" }) {
            entry.strings[index].value = .regular(title)
        } else {
            entry.strings.append(.init(key: "Title", value: .regular(title)))
        }
    }
}
