#!/usr/bin/swift
import Foundation
import Darwin

// Option 1: ioctl(TIOCGWINSZ)
func getTerminalWidthIOctl() -> Int {
    var size = winsize()
    // Try stdout first, then stderr
    let result = Darwin.ioctl(fileno(stdout), UInt(TIOCGWINSZ), &size)
    if result != 0 || size.ws_col == 0 {
        Darwin.ioctl(fileno(stderr), UInt(TIOCGWINSZ), &size)
    }
    return Int(size.ws_col) > 0 ? Int(size.ws_col) : 80
}

// Option 2: COLUMNS environment variable
func getTerminalWidthEnv() -> Int {
    if let columns = ProcessInfo.processInfo.environment["COLUMNS"],
       let width = Int(columns) {
        return width
    }
    return 80  // fallback
}

// Option 3: `tput cols` command
func getTerminalWidthTput() -> Int {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tput")
    process.arguments = ["cols"]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let width = Int(output) {
            return width
        }
    } catch {
        print("Error running tput: \(error)")
    }
    return 80  // fallback
}

// Test all three
print("Testing terminal width detection methods:")
print()

let ioctl = getTerminalWidthIOctl()
print("1. ioctl(TIOCGWINSZ): \(ioctl)")

let env = getTerminalWidthEnv()
print("2. COLUMNS env var: \(env)")

let tput = getTerminalWidthTput()
print("3. tput cols: \(tput)")

print()
print("Actual terminal width should be: \(ioctl) (ioctl is most reliable)")
