import Foundation

enum LocalParakeetModelStoreTests {
    static func run() {
        validatesMarksAndRemovesOnlyTheModelCache()
        rejectsModifiedModelAssets()
    }

    private static func validatesMarksAndRemovesOnlyTheModelCache() {
        withStore { store, assetURL in
            try Data("hello".utf8).write(to: assetURL)
            try store.validateDownloadedModel()
            try store.markInstalled()
            TestSupport.expect(store.isInstalled, "Verified local model was not reported as installed")

            let unrelated = store.cacheRoot.appendingPathComponent("keep-me.txt")
            try Data("safe".utf8).write(to: unrelated)
            try store.removeModel()
            TestSupport.expect(!store.isInstalled, "Removed local model remains installed")
            TestSupport.expect(
                FileManager.default.fileExists(atPath: unrelated.path),
                "Removing the model deleted an unrelated cache file"
            )
        }
    }

    private static func rejectsModifiedModelAssets() {
        withStore { store, assetURL in
            try Data("HELLO".utf8).write(to: assetURL)
            do {
                try store.validateDownloadedModel()
                TestSupport.expect(false, "Modified model asset passed its SHA-256 check")
            } catch LocalParakeetModelError.integrityCheckFailed {
                TestSupport.expect(true, "Modified model asset correctly rejected")
            }
        }
    }

    private static func withStore(_ body: (LocalParakeetModelStore, URL) throws -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-local-model-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = LocalParakeetModelAsset(
            relativePath: "test/asset.bin",
            byteCount: 5,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        let store = LocalParakeetModelStore(cacheRoot: root, assets: [asset])
        let assetURL = store.modelDirectory.appendingPathComponent(asset.relativePath)
        do {
            try FileManager.default.createDirectory(
                at: assetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try body(store, assetURL)
        } catch {
            fatalError("Local model store test failed: \(error)")
        }
    }
}
