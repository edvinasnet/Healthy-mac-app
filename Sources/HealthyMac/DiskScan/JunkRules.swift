import Darwin
import Foundation

/// A folder that can be regenerated (build output, dependency install, download cache).
struct JunkRule {
    let kind: String
    let note: String
}

enum JunkRules {
    private struct NameRule {
        let names: [String]
        /// Any of these must exist next to the folder (e.g. package.json next to node_modules).
        var siblings: [String] = []
        /// Any of these must exist inside the folder (e.g. pyvenv.cfg inside .venv).
        var inside: [String] = []
        let kind: String
        let note: String

        var unconditional: Bool { siblings.isEmpty && inside.isEmpty }
    }

    private static let nameRules: [NameRule] = [
        NameRule(names: ["node_modules"], siblings: ["package.json"],
                 kind: "node_modules", note: "Restore with npm / pnpm / yarn / bun install"),
        NameRule(names: [".next"], siblings: ["package.json", "next.config.js", "next.config.mjs", "next.config.ts"],
                 kind: "Next.js build", note: "Rebuilt by next dev / next build"),
        NameRule(names: [".nuxt", ".output"], siblings: ["nuxt.config.ts", "nuxt.config.js"],
                 kind: "Nuxt build", note: "Rebuilt by nuxt dev / build"),
        NameRule(names: [".svelte-kit"], siblings: ["svelte.config.js", "package.json"],
                 kind: "SvelteKit build", note: "Rebuilt by vite"),
        NameRule(names: [".turbo"], kind: "Turborepo cache", note: "Local task cache"),
        NameRule(names: [".parcel-cache"], kind: "Parcel cache", note: "Bundler cache"),
        NameRule(names: [".angular"], siblings: ["angular.json"], kind: "Angular cache", note: "Build cache"),
        NameRule(names: [".expo"], siblings: ["app.json", "package.json"], kind: "Expo cache", note: "Dev server cache"),
        NameRule(names: ["target"], siblings: ["Cargo.toml"], kind: "Rust build", note: "Rebuilt by cargo build"),
        NameRule(names: ["target"], siblings: ["pom.xml"], kind: "Maven build", note: "Rebuilt by mvn package"),
        NameRule(names: ["build", ".gradle"],
                 siblings: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
                 kind: "Gradle build", note: "Rebuilt by gradle"),
        NameRule(names: ["build", ".dart_tool"], siblings: ["pubspec.yaml"], kind: "Flutter / Dart build", note: "Rebuilt by flutter build / pub get"),
        NameRule(names: ["Pods"], siblings: ["Podfile"], kind: "CocoaPods", note: "Restore with pod install"),
        NameRule(names: [".build"], siblings: ["Package.swift"], kind: "SwiftPM build", note: "Rebuilt by swift build"),
        NameRule(names: ["DerivedData"], kind: "Xcode DerivedData", note: "Rebuilt by Xcode"),
        NameRule(names: ["cmake-build-debug", "cmake-build-release"], siblings: ["CMakeLists.txt"],
                 kind: "CMake build", note: "Rebuilt by CMake"),
        NameRule(names: [".venv", "venv", "env", ".virtualenv"], inside: ["pyvenv.cfg"],
                 kind: "Python virtualenv", note: "Recreate with python -m venv / uv sync"),
        NameRule(names: [".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox"], kind: "Python tool cache", note: "Recreated automatically"),
        NameRule(names: [".terraform"], kind: "Terraform providers", note: "Restore with terraform init"),
        NameRule(names: [".zig-cache", "zig-cache"], kind: "Zig cache", note: "Recreated automatically"),
    ]

    private static let byName: [String: [NameRule]] = {
        var map: [String: [NameRule]] = [:]
        for rule in nameRules {
            for name in rule.names { map[name, default: []].append(rule) }
        }
        return map
    }()

    /// Well-known global caches (absolute paths).
    static let pathRules: [String: JunkRule] = {
        let home = NSHomeDirectory()
        let rules: [(String, String, String)] = [
            (".npm/_cacache", "npm cache", "Re-downloaded on demand"),
            ("Library/Caches/Yarn", "Yarn cache", "Re-downloaded on demand"),
            ("Library/pnpm/store", "pnpm store", "Re-downloaded on demand (pnpm store prune is gentler)"),
            (".pnpm-store", "pnpm store", "Re-downloaded on demand"),
            ("Library/Caches/pnpm", "pnpm cache", "Re-downloaded on demand"),
            (".bun/install/cache", "Bun cache", "Re-downloaded on demand"),
            (".cache/pip", "pip cache", "Re-downloaded on demand"),
            ("Library/Caches/pip", "pip cache", "Re-downloaded on demand"),
            (".cache/uv", "uv cache", "Re-downloaded on demand"),
            ("Library/Caches/Homebrew", "Homebrew cache", "Old downloads (brew cleanup does the same)"),
            (".gradle/caches", "Gradle cache", "Re-downloaded on demand"),
            (".m2/repository", "Maven repository", "Re-downloaded on demand"),
            (".cargo/registry", "Cargo registry", "Re-downloaded on demand"),
            ("go/pkg/mod", "Go module cache", "Re-downloaded on demand"),
            ("Library/Caches/go-build", "Go build cache", "Recreated automatically"),
            (".cocoapods/repos", "CocoaPods specs", "Re-downloaded on demand"),
            ("Library/Caches/CocoaPods", "CocoaPods cache", "Re-downloaded on demand"),
            ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData", "Rebuilt by Xcode"),
            ("Library/Developer/Xcode/Archives", "Xcode archives", "Old app builds — keep if you need dSYMs"),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode device support", "Recreated when a device connects"),
            ("Library/Developer/CoreSimulator/Caches", "Simulator caches", "Recreated automatically"),
            ("Library/Caches/ms-playwright", "Playwright browsers", "Restore with npx playwright install"),
            (".cache/puppeteer", "Puppeteer browsers", "Re-downloaded on demand"),
            (".cache/huggingface", "Hugging Face models", "AI models — large re-download"),
            (".ollama/models", "Ollama models", "AI models — re-pull with ollama pull"),
            ("Library/Caches/JetBrains", "JetBrains caches", "IDE indexes, rebuilt automatically"),
        ]
        var map: [String: JunkRule] = [:]
        for (rel, kind, note) in rules { map[home + "/" + rel] = JunkRule(kind: kind, note: note) }
        return map
    }()

    /// `path` is the display path (firmlinked form, e.g. /Users/…).
    static func match(name: String, path: String) -> JunkRule? {
        if let rule = pathRules[path] { return rule }
        guard let rules = byName[name] else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        for rule in rules {
            if rule.unconditional { return JunkRule(kind: rule.kind, note: rule.note) }
            if rule.siblings.contains(where: { access(parent + "/" + $0, F_OK) == 0 })
                || rule.inside.contains(where: { access(path + "/" + $0, F_OK) == 0 }) {
                return JunkRule(kind: rule.kind, note: rule.note)
            }
        }
        return nil
    }

    /// Hint shown next to large files.
    static func largeFileHint(_ path: String) -> String? {
        let lower = path.lowercased()
        if lower.hasSuffix("docker.raw") { return "Docker disk image — shrink with docker system prune, don't delete" }
        if lower.hasPrefix("/system/") { return "System-managed (e.g. remove simulators in Xcode → Settings → Components)" }
        if lower.contains("/.ollama/models/") { return "Ollama model" }
        if lower.contains("/.cache/huggingface/") { return "Hugging Face model" }
        if lower.contains("/coresimulator/") { return "iOS Simulator data" }
        if lower.contains("/mobilesync/backup/") { return "iPhone / iPad backup" }
        for ext in [".dmg", ".iso", ".pkg"] where lower.hasSuffix(ext) { return "Installer / disk image" }
        if lower.hasSuffix(".ipsw") { return "Device firmware" }
        if lower.hasSuffix(".zip") || lower.hasSuffix(".tar.gz") || lower.hasSuffix(".7z") { return "Archive" }
        if lower.hasPrefix("/private/var/vm/") { return "macOS swap / sleep image — managed by the system" }
        return nil
    }
}
