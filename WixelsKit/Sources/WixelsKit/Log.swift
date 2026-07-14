// Log — the one stderr writer. Every diagnostic wixels prints (config fallbacks,
// dlopen failures, duplicate/missing kinds, first-run scaffolding) goes through
// here so they all share the `wixels:` prefix and a single channel.

import Foundation

public enum Log {
    public static func note(_ msg: String) {
        FileHandle.standardError.write(Data("wixels: \(msg)\n".utf8))
    }
}
