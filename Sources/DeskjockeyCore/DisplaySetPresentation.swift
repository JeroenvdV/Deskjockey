import Foundation

/// Builds UI state from domain data.
enum DisplaySetPresentation {
    static func make(_ displays: [DisplaySnapshot], displaySetClass: DisplaySetClass, mapping: [String: Int],
                     lastProcessedAt: Date?) -> DisplaySetState {
        var state = DisplaySetState()
        state.hasSavedScreenConfiguration = true
        state.lastProcessedAt = lastProcessedAt
        let plan = try? ScreenConfigurationLogic.plan(displays, configuration: displaySetClass.configuration, mapping: mapping)
        let normalized = (try? ScreenConfigurationLogic.normalized(displays)) ?? []
        state.matchesScreenConfiguration = plan.map { ScreenConfigurationLogic.matches(displays, plan: $0) } ?? false
        state.summaries = displays.sorted { $0.runtimeID < $1.runtimeID }.map { display in
            let target = plan?.targets.first { $0.runtimeID == display.runtimeID }
            let actual = normalized.first { $0.runtimeID == display.runtimeID }
            return DisplaySummary(displayName: display.displayName, pixelSize: display.mode.pixelSize, isBuiltIn: display.isBuiltIn,
                                  matchesScreenConfiguration: target != nil && target?.targetFrame == actual?.frame
                                    && target?.targetMode == actual?.mode && target?.isMain == actual?.isMain)
        }
        let ordered = displays.filter { !$0.isBuiltIn && !$0.isMirrored }.sorted { $0.runtimeID < $1.runtimeID }
        for (i, first) in ordered.enumerated() {
            for second in ordered.dropFirst(i + 1) where first.modelID == second.modelID {
                state.swapCandidates.append(DisplaySwapCandidate(firstRuntimeID: first.runtimeID, secondRuntimeID: second.runtimeID,
                                                         title: "Swap \(first.displayName) / \(second.displayName)"))
            }
        }
        return state
    }
}
