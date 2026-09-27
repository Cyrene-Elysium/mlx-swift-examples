// Download-stall probe: replays the exact call chain the iOS app uses
// (HubClient.downloadSnapshot over mlx-community/Qwen3-4B-4bit) and
// captures a forensic timeline: per-sample progress, blob/incomplete/tmp
// file sizes on stall, and cache layout on completion.
import Foundation
import HuggingFace

final class SampleState: @unchecked Sendable {
    let lock = NSLock()
    var lastBytes: Int64 = 0
    var lastDate = Date()
    var lastPrint = Date.distantPast
}

let repoName = "mlx-community/Qwen3-4B-4bit"
let repo = Repo.ID(rawValue: repoName)!
let cacheDir = URL(fileURLWithPath: "/tmp/hf-probe-cache")
let repoDir = cacheDir.appending(path: "models--mlx-community--Qwen3-4B-4bit")
let start = Date()
let state = SampleState()

func forensicDump(reason: String) {
    let fm = FileManager.default
    print("", flush: true)
    print("=== FORENSIC DUMP (\(reason)) ===", flush: true)
    for sub in ["blobs", "snapshots"] {
        let dir = repoDir.appending(path: sub)
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else {
            print("\(sub)/: <missing>", flush: true)
            continue
        }
        for entry in entries {
            let path = dir.appending(path: entry)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                let files = (try? fm.subpathsOfDirectory(atPath: path.path)) ?? []
                let total = files.compactMap { f -> Int64? in
                    let fp = path.appending(path: f)
                    let attrs = try? fm.attributesOfItem(atPath: fp.path)
                    return (attrs?[.size] as? NSNumber)?.int64Value
                }.reduce(0, +)
                print("\(sub)/\(entry)/ -> \(files.count) files, \(total) bytes", flush: true)
                for f in files {
                    let fp = path.appending(path: f)
                    let attrs = try? fm.attributesOfItem(atPath: fp.path)
                    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                    print("    \(f)  \(size) bytes", flush: true)
                }
            } else {
                let attrs = try? fm.attributesOfItem(atPath: path.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                print("\(sub)/\(entry)  \(size) bytes", flush: true)
            }
        }
    }
    // URLSession download temp files: bytes physically received sit here
    // while a transfer is in flight. Their sizes tell us whether the
    // transfer is actually progressing while the Progress object is frozen.
    let tmpDir = FileManager.default.temporaryDirectory
    if let tmps = try? fm.contentsOfDirectory(atPath: tmpDir.path) {
        for t in tmps where t.hasPrefix("hf-download-") {
            let attrs = try? fm.attributesOfItem(atPath: tmpDir.appending(path: t).path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            print("TMP  \(t)  \(size) bytes", flush: true)
        }
    }
}

func run() async {
    let client = HubClient(cache: HubCache(cacheDirectory: cacheDir))
    print("probe start \(repoName), cache \(cacheDir.path)", flush: true)

    do {
        let url = try await client.downloadSnapshot(
            of: repo,
            matching: ["*.safetensors", "*.json", "*.jinja"]
        ) { progress in
            state.lock.lock()
            defer { state.lock.unlock() }
            let bytes = progress.completedUnitCount
            let total = progress.totalUnitCount
            let now = Date()
            let dt = now.timeIntervalSince(start)
            let dtSample = now.timeIntervalSince(state.lastDate)
            let inst = Double(bytes - state.lastBytes) / max(dtSample, 0.001) / 1e6
            state.lastBytes = bytes
            state.lastDate = now
            if now.timeIntervalSince(state.lastPrint) >= 0.5 {
                state.lastPrint = now
                print(
                    String(
                        format: "[%7.2fs] %12d / %12d  (%5.2f%%)  %7.2f MB/s", dt, bytes, total,
                        progress.fractionCompleted * 100, inst),
                    flush: true)
            }
        }
        let dt = Date().timeIntervalSince(start)
        print(String(format: "DONE in %.1fs -> %@", dt, url.path), flush: true)
        forensicDump(reason: "success")
        exit(0)
    } catch {
        let dt = Date().timeIntervalSince(start)
        print("ERROR after \(dt)s: \(error)", flush: true)
        forensicDump(reason: "error")
        exit(1)
    }
}

let mainTask = Task { await run() }

// Watchdog: if the snapshot does not finish in 8 minutes, dump state and bail.
Task {
    try? await Task.sleep(nanoseconds: 8 * 60 * 1_000_000_000)
    let dt = Date().timeIntervalSince(start)
    print("WATCHDOG: no completion after \(dt)s — treating as stall.", flush: true)
    forensicDump(reason: "watchdog")
    exit(2)
}

dispatchMain()
