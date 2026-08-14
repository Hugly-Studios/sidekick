#!/bin/bash
# Scaffolds a feature module: sources, test, Project.swift line, AppEnvironment
# registration. Does not run tuist generate — that happens on the next build.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

name="${1:-}"
if [[ -z "$name" ]]; then
	echo "usage: scripts/new-module.sh Name" >&2
	exit 2
fi

if [[ ! "$name" =~ ^[A-Z][A-Za-z0-9]+$ ]]; then
	echo "new-module: NAME must be PascalCase, e.g. Awake" >&2
	exit 2
fi

id="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
sources="$repo_root/Features/$name/Sources"
tests="$repo_root/Features/$name/Tests"

if [[ -d "$sources" ]]; then
	echo "new-module: Features/$name already exists" >&2
	exit 1
fi

mkdir -p "$sources" "$tests"

cat >"$sources/${name}Feature.swift" <<EOF
import AppCore
import SwiftUI
import SystemKit

@MainActor
public final class ${name}Feature: Feature {
    public static let descriptor = FeatureDescriptor(
        id: "$id",
        title: "$name",
        summary: "TODO: describe what this module does",
        symbolName: "square.grid.2x2",
        requiredPermissions: [],
        isEnabledByDefault: false
    )

    private let context: FeatureContext

    public convenience init(context: FeatureContext) {
        self.init(context: context, clock: SystemClock())
    }

    init(context: FeatureContext, clock: some Clock) {
        self.context = context
        _ = clock
    }

    public func activate() async throws {}

    public func deactivate() async {}

    public var commands: [Command] {
        [
            Command(id: "$id.status", title: "Статус $name", symbolName: "info.circle") { _ in
                "ok"
            }
        ]
    }

    public func makeSettingsView() -> AnyView {
        AnyView(Text("$name"))
    }
}
EOF

cat >"$tests/${name}FeatureTests.swift" <<EOF
import AppCore
import TestSupport
import Testing

@testable import $name

@MainActor
struct ${name}FeatureTests {
    @Test func constructsWithInjectedDependencies() {
        let feature = ${name}Feature(
            context: TestFeatureContext.make(id: "$id"),
            clock: FakeClock()
        )
        #expect(type(of: feature).descriptor.id.rawValue == "$id")
    }
}
EOF

python3 - "$name" <<'PY'
import pathlib
import re
import sys

name = sys.argv[1]


def insert_before(text, anchor, addition, what):
    """Anchors on the Workspaces entry, which every list already has."""
    if addition in text:
        return text
    if anchor not in text:
        sys.exit(f"new-module: could not find {what}")
    return text.replace(anchor, addition + anchor, 1)


project_path = pathlib.Path("Project.swift")
text = project_path.read_text()

text = insert_before(
    text,
    '        + Module.feature(\n            "Workspaces",\n',
    f"""        + Module.feature(
            "{name}",
            dependencies: [.target(name: "SystemKit")],
            testDependencies: [.target(name: "TestSupport")]
        )
""",
    "the Workspaces feature block in Project.swift",
)

# Without this the app does not link the module and `import <Name>` fails.
text = insert_before(
    text,
    '                .target(name: "Workspaces"),\n',
    f'                .target(name: "{name}"),\n',
    "the app target dependencies in Project.swift",
)

# Without this `make verify` and CI never run the module's tests.
text = insert_before(
    text,
    '                .testableTarget(target: .target("WorkspacesTests")),\n',
    f'                .testableTarget(target: .target("{name}Tests")),\n',
    "the test action of the Sidekick scheme in Project.swift",
)

project_path.write_text(text)

env_path = pathlib.Path("Apps/Mac/Sources/AppEnvironment.swift")
env_text = env_path.read_text()

if f"import {name}\n" not in env_text:
    env_text = env_text.replace("import Workspaces\n", f"import {name}\nimport Workspaces\n", 1)

# Prepend into whatever the list already holds, so the second module works too.
if f"{name}Feature.self" not in env_text:
    pattern = re.compile(r"(static var featureTypes: \[any Feature\.Type\] \{\s*\[)")
    env_text, count = pattern.subn(rf"\g<1>{name}Feature.self, ", env_text, count=1)
    if count == 0:
        sys.exit("new-module: could not find featureTypes in AppEnvironment.swift")

env_path.write_text(env_text)
PY

echo "new-module: created Features/$name"
echo "new-module: registered $name in Project.swift and AppEnvironment"
echo "new-module: run make generate, then make verify"
