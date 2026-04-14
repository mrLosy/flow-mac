import Foundation

enum DebugLog {
    private static let url: URL = {
        // App Sandbox: write to app container, not Desktop
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("flowmac_debug.log")
    }()

    /// Call once to print log location
    static func printLocation() {
        NSLog("[FlowMac] DebugLog path: \(url.path)")
    }

    static func log(_ msg: String, file: String = #file, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        let entry = "\(Date()) \(filename):\(line) — \(msg)\n"
        let data = entry.data(using: .utf8) ?? Data()

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data)
        }
    }

    static func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "(empty)"
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
