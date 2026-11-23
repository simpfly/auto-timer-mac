import Foundation

// The approved source is kept in version control; regenerate all macOS sizes.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
}
let source = root.appendingPathComponent("assets/AppIcon-source.png").path
try FileManager.default.createDirectory(at: root.appendingPathComponent("AppIcon.iconset"), withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = String(size * scale)
        let suffix = scale == 2 ? "@2x" : ""
        let output = root.appendingPathComponent("AppIcon.iconset/icon_\(size)x\(size)\(suffix).png").path
        try run("/usr/bin/sips", ["-z", pixels, pixels, source, "--out", output])
    }
}
for output in ["AppIcon_1024.png", "assets/icon.png"] {
    try run("/usr/bin/sips", ["-z", "1024", "1024", source, "--out", root.appendingPathComponent(output).path])
}
// Package the PNG representations directly into the standard ICNS container.
func lengthBytes(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
let entries = [("icp4", "16x16"), ("icp5", "32x32"), ("icp6", "32x32@2x"),
               ("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"),
               ("ic10", "512x512@2x"), ("ic11", "16x16@2x"),
               ("ic12", "32x32@2x"), ("ic13", "128x128@2x"), ("ic14", "256x256@2x")]
var body = Data()
for (type, name) in entries {
    let png = try Data(contentsOf: root.appendingPathComponent("AppIcon.iconset/icon_\(name).png"))
    body.append(Data(type.utf8))
    body.append(lengthBytes(png.count + 8))
    body.append(png)
}
var container = Data("icns".utf8)
container.append(lengthBytes(body.count + 8))
container.append(body)
try container.write(to: root.appendingPathComponent("AppIcon.icns"))
