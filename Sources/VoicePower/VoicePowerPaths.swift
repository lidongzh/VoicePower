import Foundation

enum VoicePowerPaths {
    static var applicationSupportURL: URL {
        URL(fileURLWithPath: "~/Library/Application Support/VoicePower".expandedTildePath)
    }

    static var runtimeRootURL: URL {
        applicationSupportURL.appendingPathComponent("Runtime", isDirectory: true)
    }

    static var runtimeVenvURL: URL {
        runtimeRootURL.appendingPathComponent("venv", isDirectory: true)
    }

    static var runtimePythonURL: URL {
        runtimeVenvURL.appendingPathComponent("bin/python3")
    }

    static var cacheRootURL: URL {
        applicationSupportURL.appendingPathComponent("Cache", isDirectory: true)
    }

    static var pipCacheURL: URL {
        cacheRootURL.appendingPathComponent("pip", isDirectory: true)
    }

    static var huggingFaceCacheURL: URL {
        cacheRootURL.appendingPathComponent("huggingface", isDirectory: true)
    }

    static var markersURL: URL {
        runtimeRootURL.appendingPathComponent("markers", isDirectory: true)
    }

    static var runtimeReadyMarkerURL: URL {
        markersURL.appendingPathComponent("runtime.ready")
    }

    static var bundledScriptsURL: URL? {
        Bundle.main.resourceURL
    }

    static var bundledRuntimeSeedURL: URL? {
        bundledScriptsURL?.appendingPathComponent("RuntimeSeed", isDirectory: true)
    }

    static var bundledRuntimeVenvURL: URL? {
        bundledRuntimeSeedURL?.appendingPathComponent("venv", isDirectory: true)
    }

    static var bundledRuntimeManifestURL: URL? {
        bundledRuntimeSeedURL?.appendingPathComponent("manifest.json")
    }

    static var installedBundledRuntimeManifestURL: URL {
        runtimeRootURL.appendingPathComponent("bundled-runtime-manifest.json")
    }

    static var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func scriptURL(named scriptName: String) -> URL {
        let fileManager = FileManager.default
        if let bundledScriptsURL {
            let bundled = bundledScriptsURL.appendingPathComponent(scriptName)
            if fileManager.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        return repoRootURL.appendingPathComponent("scripts/\(scriptName)")
    }

    static func markerURL(kind: String, model: String) -> URL {
        let sanitized = model
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return markersURL.appendingPathComponent("\(kind)-\(sanitized).ready")
    }
}
