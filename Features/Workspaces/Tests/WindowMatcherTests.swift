import Testing

@testable import Workspaces

private func snapshot(_ bundleID: String, _ title: String) -> WindowSnapshot {
    WindowSnapshot(
        bundleID: bundleID,
        appName: bundleID,
        title: title,
        frame: FrameSnapshot(x: 0, y: 0, width: 100, height: 100),
        isMinimized: false,
        isFullscreen: false
    )
}

struct WindowMatcherTests {
    @Test func prefersExactTitle() {
        let pairs = WindowMatcher.pair(
            snapshots: [snapshot("com.apple.Safari", "Документация")],
            candidates: [
                MatchCandidate(id: 1, bundleID: "com.apple.Safari", title: "Почта"),
                MatchCandidate(id: 2, bundleID: "com.apple.Safari", title: "Документация"),
            ]
        )

        #expect(pairs[0] == 2)
    }

    @Test func neverMatchesAcrossApps() {
        let pairs = WindowMatcher.pair(
            snapshots: [snapshot("com.apple.Safari", "Документация")],
            candidates: [
                MatchCandidate(id: 1, bundleID: "com.apple.Terminal", title: "Документация")
            ]
        )

        #expect(pairs.isEmpty)
    }

    @Test func doesNotReuseTheSameWindowTwice() {
        let pairs = WindowMatcher.pair(
            snapshots: [
                snapshot("com.apple.TextEdit", "Заметки"),
                snapshot("com.apple.TextEdit", "Заметки"),
            ],
            candidates: [
                MatchCandidate(id: 7, bundleID: "com.apple.TextEdit", title: "Заметки"),
                MatchCandidate(id: 8, bundleID: "com.apple.TextEdit", title: "Черновик"),
            ]
        )

        #expect(pairs[0] == 7)
        #expect(pairs[1] == 8)
    }

    @Test func fallsBackToOrderWhenTitlesChanged() {
        let pairs = WindowMatcher.pair(
            snapshots: [
                snapshot("com.figma.Desktop", "Проект A"),
                snapshot("com.figma.Desktop", "Проект B"),
            ],
            candidates: [
                MatchCandidate(id: 11, bundleID: "com.figma.Desktop", title: "Другое"),
                MatchCandidate(id: 12, bundleID: "com.figma.Desktop", title: "Совсем другое"),
            ]
        )

        #expect(pairs[0] == 11)
        #expect(pairs[1] == 12)
    }

    @Test func matchesRenamedDocumentByPartialTitle() {
        let pairs = WindowMatcher.pair(
            snapshots: [snapshot("com.microsoft.VSCode", "Sidekick — Project.swift")],
            candidates: [
                MatchCandidate(id: 3, bundleID: "com.microsoft.VSCode", title: "Другой проект"),
                MatchCandidate(
                    id: 4,
                    bundleID: "com.microsoft.VSCode",
                    title: "Sidekick — Project.swift — изменён"
                ),
            ]
        )

        #expect(pairs[0] == 4)
    }

    @Test func ignoresShortTitlesForPartialMatching() {
        // A title like "1" must not win over positional order.
        let pairs = WindowMatcher.pair(
            snapshots: [snapshot("com.apple.Terminal", "1")],
            candidates: [
                MatchCandidate(id: 5, bundleID: "com.apple.Terminal", title: "первый — 1 — окно"),
                MatchCandidate(id: 6, bundleID: "com.apple.Terminal", title: "1"),
            ]
        )

        #expect(pairs[0] == 6)
    }

    @Test func matchesNothingWhenAppIsMissing() {
        let pairs = WindowMatcher.pair(
            snapshots: [snapshot("com.apple.Safari", "Документация")],
            candidates: []
        )

        #expect(pairs.isEmpty)
    }
}
