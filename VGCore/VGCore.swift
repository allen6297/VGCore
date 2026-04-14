//
//  VGCore.swift
//  VGCore
//
//  Created by Kalob Allen on 4/11/26.
//

import Foundation

public enum VGCoreInfo {
    public static let coreVersion = "1.0.0"
}

func diffByID<ID: Hashable & Comparable & Sendable, Value: Equatable>(
    old: [ID: Value],
    new: [ID: Value]
) -> ReloadDelta<ID> {
    let oldIDs = Set(old.keys)
    let newIDs = Set(new.keys)

    return ReloadDelta(
        added: Array(newIDs.subtracting(oldIDs)).sorted(),
        removed: Array(oldIDs.subtracting(newIDs)).sorted(),
        updated: Array(oldIDs.intersection(newIDs).filter { id in
            old[id] != new[id]
        }).sorted()
    )
}
