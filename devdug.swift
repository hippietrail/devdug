#!/usr/bin/swift

import Foundation

// MARK: - ANSI Terminal Control

struct ANSI {
    static let reset = "\u{1B}[0m"
    static let bold = "\u{1B}[1m"
    static let dim = "\u{1B}[2m"
    static let cyan = "\u{1B}[36m"
    static let green = "\u{1B}[32m"
    static let yellow = "\u{1B}[33m"
    
    // Cursor control
    static let saveCursor = "\u{1B}[s"
    static let restoreCursor = "\u{1B}[u"
    static func moveTo(row: Int, col: Int) -> String {
        return "\u{1B}[\(row);\(col)H"
    }
    static func clearLine() -> String {
        return "\u{1B}[K"
    }
    
    // Scroll regions
    static func setScrollRegion(top: Int, bottom: Int) -> String {
        return "\u{1B}[\(top);\(bottom)r"
    }
    static let resetScrollRegion = "\u{1B}[r"
}

class TerminalUI {
    private var isSetup = false
    private var projectCounts: [String: Int] = [:]
    
    init() {}
    
    func recordProject(type: String) {
        projectCounts[type, default: 0] += 1
    }
    
    private func buildStatusLine() -> String {
        let counts = projectCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " | ")
        
        let totalProjects = projectCounts.values.reduce(0, +)
        return "Total: \(totalProjects) | \(counts)"
    }
    
    func updateStatus() {
        let statusMsg = buildStatusLine()
        
        // Jump to last line, update, jump back
        print(ANSI.saveCursor, terminator: "")
        print(ANSI.moveTo(row: 9999, col: 1), terminator: "")  // Jump to bottom (terminal will clip to last line)
        print("\(ANSI.dim)⧏ \(statusMsg)\(ANSI.clearLine())\(ANSI.reset)", terminator: "")
        print(ANSI.restoreCursor, terminator: "")
        fflush(stdout)
    }
    
    func setup() {
        // No scroll region setup needed - just print normally
        isSetup = true
    }
    
    func cleanup() {
        // Nothing to clean up
        isSetup = false
    }
    
    func printMessage(_ message: String) {
        print(message)
        fflush(stdout)
    }
}

// MARK: - Configuration & Types

struct Config {
    let dryRun: Bool
    let listOnly: Bool
    let verbose: Bool
    let confirmationCount: Int // 0 = dry-run only, 1+ = require N confirmations
}

struct ProjectInfo {
    let path: String
    let name: String
    let type: String // "xcode", "intellij", "android-studio", "eclipse", "npm", "cargo", etc.
    let size: UInt64 // in bytes
    let lastModified: Date
}

// MARK: - Argument Parser

func parseArgs(_ args: [String]) -> Config {
    var dryRun = true
    var listOnly = false
    var verbose = false
    var confirmations = 0
    
    for arg in args.dropFirst() {
        switch arg {
        case "--clean":
            dryRun = false
        case "--list":
            listOnly = true
        case "-v", "--verbose":
            verbose = true
        case "-y", "--yes":
            confirmations += 1
        case "--force":
            confirmations = 2
        case "--help", "-h":
            printHelp()
            exit(0)
        default:
            if arg.starts(with: "-") {
                // Handle combined flags like -yy, -vv, etc.
                if arg.starts(with: "--") {
                    print("Unknown flag: \(arg)")
                    printHelp()
                    exit(1)
                }
                
                // Process combined short flags
                for char in arg.dropFirst() {
                    switch char {
                    case "y":
                        confirmations += 1
                    case "v":
                        verbose = true
                    case "h":
                        printHelp()
                        exit(0)
                    default:
                        print("Unknown flag: -\(char)")
                        printHelp()
                        exit(1)
                    }
                }
            }
        }
    }
    
    return Config(
        dryRun: dryRun,
        listOnly: listOnly,
        verbose: verbose,
        confirmationCount: confirmations
    )
}

func printHelp() {
    print("""
    devdug - Clean up forgotten dev projects
    
    USAGE:
        devdug [OPTIONS]
    
    OPTIONS:
        --list              List all discovered projects (default behavior)
        --clean             Enable cleanup mode (requires confirmations)
        --yes, -y           Add confirmation (use twice: -yy for double-confirm)
        --force             Skip confirmations (dangerous!)
        -v, --verbose       Verbose output
        -h, --help          Show this help
    
    EXAMPLES:
        devdug                    # List projects (dry-run)
        devdug --clean            # Show what will be cleaned (dry-run)
        devdug --clean -yy        # Clean with double confirmation
        devdug --clean --force    # Clean without confirmation (dangerous!)
    """)
}

// MARK: - IDE Detection & Project Locations

func getInstalledIDEs() -> Set<String> {
    let fm = FileManager.default
    var installed: Set<String> = []
    
    // Check for IDEs in /Applications
    let appPaths = [
        "/Applications/Xcode.app": "xcode",
        "/Applications/IntelliJ IDEA.app": "intellij",
        "/Applications/RustRover.app": "rustrover",
        "/Applications/CLion.app": "clion",
        "/Applications/GoLand.app": "goland",
        "/Applications/PyCharm.app": "pycharm",
        "/Applications/WebStorm.app": "webstorm",
        "/Applications/AppCode.app": "appcode",
        "/Applications/Android Studio.app": "android-studio",
        "/Applications/Eclipse.app": "eclipse",
    ]
    
    for (path, name) in appPaths {
        if fm.fileExists(atPath: path) {
            installed.insert(name)
        }
    }
    
    return installed
}

func getStandardIDELocations() -> [(path: String, ide: String)] {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var locations: [(String, String)] = []
    
    let ideMap: [(path: String, ide: String)] = [
        // IntelliJ variants
        ("\(homeDir)/IdeaProjects", "idea"),
        ("\(homeDir)/RustroverProjects", "rustrover"),
        ("\(homeDir)/CLionProjects", "clion"),
        ("\(homeDir)/GolandProjects", "goland"),
        ("\(homeDir)/PyCharmProjects", "pycharm"),
        ("\(homeDir)/WebstormProjects", "webstorm"),
        ("\(homeDir)/AppCodeProjects", "appcode"),
        
        // Android
        ("\(homeDir)/Android Studio Projects", "android-studio"),
        
        // Eclipse
        ("\(homeDir)/eclipse-workspace", "eclipse"),
        ("\(homeDir)/eclipse", "eclipse"),
        
        // Xcode (no centralized location, but check common spots)
        ("\(homeDir)/Library/Developer/Xcode/DerivedData", "xcode"),
        
        // Generic
        ("\(homeDir)/Projects", "generic"),
        ("\(homeDir)/Source", "generic"),
        ("\(homeDir)/Code", "generic"),
    ]
    
    for (path, ide) in ideMap {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            locations.append((path, ide))
        }
    }
    
    return locations
}

func getIDECacheLocations() -> [String] {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    
    return [
        // Xcode
        "\(homeDir)/Library/Developer/Xcode/DerivedData",
        
        // Gradle
        "\(homeDir)/.gradle/caches",
        
        // JetBrains
        "\(homeDir)/Library/Caches/JetBrains",
        "\(homeDir)/Library/Logs/JetBrains",
        
        // npm
        "\(homeDir)/.npm",
        
        // Rust
        "\(homeDir)/.cargo/registry/cache",
    ]
}

func scanHomeDirectoryForProjects(verbose: Bool = false, ui: TerminalUI? = nil) -> [ProjectInfo] {
    let fm = FileManager.default
    let homeDir = fm.homeDirectoryForCurrentUser.path
    var projects: [ProjectInfo] = []
    
    // Directories to skip entirely (common non-project dirs)
    let skipDirs = Set([
        ".Trash", ".cache", ".local", ".config", ".ssh", ".vim",
        "Library", "Applications", "Desktop", "Downloads", "Documents",
        ".git", ".gradle", ".cargo", "__pycache__",
        "venv", "env", ".venv", ".env", ".npm"
    ])
    
    // Directories that indicate we should stop descending (build artifacts, dependencies)
    let stopDescendingDirs = Set([
        "node_modules", "build", "dist", "target", ".build",
        "DerivedData", "xcarchive"
    ])
    
    guard let enumerator = fm.enumerator(atPath: homeDir) else { return [] }
    
    for case let item as String in enumerator {
        let components = item.split(separator: "/", omittingEmptySubsequences: true)
        
        // Go up to 3 levels deep from home
        if components.count > 3 {
            enumerator.skipDescendants()
            continue
        }
        
        let fullPath = "\(homeDir)/\(item)"
        var isDir: ObjCBool = false
        
        guard fm.fileExists(atPath: fullPath, isDirectory: &isDir),
              isDir.boolValue else {
            continue
        }
        
        let dirName = String(components.last ?? "")
        
        // Skip completely if in skip list or hidden
        if skipDirs.contains(dirName) || dirName.starts(with: ".") {
            enumerator.skipDescendants()
            continue
        }
        
        // Stop descending if we hit build artifacts
        if stopDescendingDirs.contains(dirName) {
            enumerator.skipDescendants()
            continue
        }
        
        // Try to detect project type
        if let type = detectProjectType(fullPath) {
            let size = getDirectorySize(fullPath)
            let attributes = try? fm.attributesOfItem(atPath: fullPath)
            let modDate = (attributes?[.modificationDate] as? Date) ?? Date()
            
            projects.append(ProjectInfo(
                path: fullPath,
                name: dirName,
                type: type,
                size: size,
                lastModified: modDate
            ))
            
            if verbose {
                let msg = "✓ Found \(dirName) (\(type)) in ~"
                ui?.printMessage(msg) ?? print(msg)
            }
            
            // Record and update status bar
            if let ui = ui {
                ui.recordProject(type: type)
                ui.updateStatus()
            }
            
            // Don't descend into projects we found
            enumerator.skipDescendants()
        }
        // If no project found, continue descending (could be a workspace dir)
        }
        
        return projects
        }

func detectProjectType(_ path: String) -> String? {
    let fm = FileManager.default
    
    // IDE-level projects (highest priority - most definitive)
    if fm.fileExists(atPath: "\(path)/.xcodeproj") {
        return "xcode"
    }
    if fm.fileExists(atPath: "\(path)/.xcworkspace") {
        return "xcode-workspace"
    }
    if fm.fileExists(atPath: "\(path)/.idea") {
        return "intellij"
    }
    
    // Language-specific package managers & config
    // Rust
    if fm.fileExists(atPath: "\(path)/Cargo.toml") {
        return "cargo"
    }
    
    // Zig
    if fm.fileExists(atPath: "\(path)/build.zig") {
        return "zig"
    }
    
    // Go
    if fm.fileExists(atPath: "\(path)/go.mod") {
        return "go"
    }
    
    // JavaScript/Node
    if fm.fileExists(atPath: "\(path)/package.json") {
        return "npm"
    }
    
    // Python
    if fm.fileExists(atPath: "\(path)/pyproject.toml") {
        return "python-poetry"
    }
    if fm.fileExists(atPath: "\(path)/setup.py") ||
       fm.fileExists(atPath: "\(path)/setup.cfg") {
        return "python-setuptools"
    }
    if fm.fileExists(atPath: "\(path)/requirements.txt") {
        return "python-pip"
    }
    
    // Java/JVM
    if fm.fileExists(atPath: "\(path)/pom.xml") {
        return "maven"
    }
    if fm.fileExists(atPath: "\(path)/build.gradle") ||
       fm.fileExists(atPath: "\(path)/build.gradle.kts") {
        return "gradle"
    }
    
    // Swift
    if fm.fileExists(atPath: "\(path)/Package.swift") {
        return "swift-spm"
    }
    
    // C/C++
    if fm.fileExists(atPath: "\(path)/CMakeLists.txt") {
        return "cmake"
    }
    if fm.fileExists(atPath: "\(path)/Makefile") {
        return "make"
    }
    
    // Build systems
    if fm.fileExists(atPath: "\(path)/build.sh") ||
       fm.fileExists(atPath: "\(path)/build.zsh") {
        return "shell-build"
    }
    
    // VCS detection as fallback (generic project)
    if fm.fileExists(atPath: "\(path)/.git") {
        // Could look inside .git/config to determine language, but not essential
        return "git-repo"
    }
    
    // Eclipse workspace detection
    if fm.fileExists(atPath: "\(path)/.metadata") {
        return "eclipse-workspace"
    }
    
    return nil
}

func getDirectorySize(_ path: String) -> UInt64 {
    let fm = FileManager.default
    var totalSize: UInt64 = 0
    
    guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
    
    for case let file as String in enumerator {
        let filePath = "\(path)/\(file)"
        do {
            let attributes = try fm.attributesOfItem(atPath: filePath)
            if let fileSize = attributes[.size] as? UInt64 {
                totalSize += fileSize
            }
        } catch {
            // Skip files we can't read
            continue
        }
    }
    
    return totalSize
}

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var size = Double(bytes)
    var unitIndex = 0
    
    while size >= 1024 && unitIndex < units.count - 1 {
        size /= 1024
        unitIndex += 1
    }
    
    let formatted = String(format: "%.1f", size)
    return "\(formatted) \(units[unitIndex])"
}

func resolveAliasOrSymlink(_ path: String) -> String {
    let fm = FileManager.default
    
    // Try to resolve as symlink first
    if let resolved = try? fm.destinationOfSymbolicLink(atPath: path) {
        return resolved
    }
    
    // For macOS aliases, try using NSURL
    let url = NSURL(fileURLWithPath: path)
    if let vals = try? url.resourceValues(forKeys: [.canonicalPathKey]),
       let resolvedURL = vals[.canonicalPathKey] as? String {
        return resolvedURL
    }
    
    return path
}

func discoverProjects(in locations: [(path: String, ide: String)], verbose: Bool = false, ui: TerminalUI? = nil) -> [ProjectInfo] {
    let fm = FileManager.default
    var projects: [ProjectInfo] = []
    
    for (location, ide) in locations {
        let resolvedPath = resolveAliasOrSymlink(location)
        
        // Check if it's actually a directory
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolvedPath, isDirectory: &isDir),
              isDir.boolValue else {
            if verbose {
                ui?.printMessage("⊘ \(location) (not a directory)") ?? print("⊘ \(location) (not a directory)")
            }
            continue
        }
        
        do {
            let contents = try fm.contentsOfDirectory(atPath: resolvedPath)
            
            for item in contents {
                let fullPath = "\(resolvedPath)/\(item)"
                var itemIsDir: ObjCBool = false
                
                guard fm.fileExists(atPath: fullPath, isDirectory: &itemIsDir),
                      itemIsDir.boolValue else {
                    continue
                }
                
                // Skip hidden directories
                if item.starts(with: ".") {
                    continue
                }
                
                if let type = detectProjectType(fullPath) {
                    let size = getDirectorySize(fullPath)
                    let attributes = try fm.attributesOfItem(atPath: fullPath)
                    let modDate = (attributes[.modificationDate] as? Date) ?? Date()
                    
                    projects.append(ProjectInfo(
                        path: fullPath,
                        name: item,
                        type: type,
                        size: size,
                        lastModified: modDate
                    ))
                    
                    if verbose {
                        let msg = "✓ Found \(item) (\(type)) in \(ide)"
                        ui?.printMessage(msg) ?? print(msg)
                    }
                    
                    // Record and update status bar
                    if let ui = ui {
                        ui.recordProject(type: type)
                        ui.updateStatus()
                    }
                }
            }
        } catch {
            if verbose {
                ui?.printMessage("✗ Error scanning \(location): \(error)") ?? print("✗ Error scanning \(location): \(error)")
            }
        }
    }
    
    return projects.sorted { $0.lastModified > $1.lastModified }
}

// MARK: - Display Functions

func printProjects(_ projects: [ProjectInfo]) {
    if projects.isEmpty {
        print("No projects discovered.")
        return
    }
    
    print("Discovered \(projects.count) project(s):\n")
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .short
    dateFormatter.timeStyle = .none
    
    for project in projects {
        let dateStr = dateFormatter.string(from: project.lastModified)
        let sizeStr = formatBytes(project.size)
        print("  📦 \(project.name)")
        print("     Type: \(project.type) | Size: \(sizeStr) | Modified: \(dateStr)")
        print("     Path: \(project.path)\n")
    }
}

func requestConfirmation(_ message: String, confirmationNumber: Int = 1) -> Bool {
    print("\n\(message)")
    if confirmationNumber > 1 {
        print("[\(confirmationNumber)/2] ", terminator: "")
    }
    print("Continue? (yes/no): ", terminator: "")
    fflush(stdout)
    
    guard let response = readLine() else { return false }
    return response.lowercased().starts(with: "y")
}

// MARK: - Main

let config = parseArgs(CommandLine.arguments)

// Set up terminal UI if verbose (before any printing)
let ui = config.verbose ? TerminalUI() : nil
ui?.setup()

if config.verbose {
    ui?.printMessage("🔍 Checking for installed IDEs...\n") ?? print("🔍 Checking for installed IDEs...\n")
    let installed = getInstalledIDEs()
    if installed.isEmpty {
        ui?.printMessage("No IDEs detected (but this is OK - scanning all standard locations)\n") ?? print("No IDEs detected (but this is OK - scanning all standard locations)\n")
    } else {
        ui?.printMessage("Detected: \(installed.sorted().joined(separator: ", "))\n") ?? print("Detected: \(installed.sorted().joined(separator: ", "))\n")
    }
}

let locations = getStandardIDELocations()
var projects = discoverProjects(in: locations, verbose: config.verbose, ui: ui)

if config.verbose {
    ui?.printMessage("\n🏠 Scanning home directory for scattered projects...\n") ?? print("\n🏠 Scanning home directory for scattered projects...\n")
}
let homeProjects = scanHomeDirectoryForProjects(verbose: config.verbose, ui: ui)
projects.append(contentsOf: homeProjects)

ui?.cleanup()

// Remove duplicates (by path)
projects = Array(Set(projects.map { $0.path })).compactMap { path in
    projects.first { $0.path == path }
}

if config.dryRun || config.listOnly {
    print("🔍 devdug - Project Discovery\n")
    print("Mode: DRY-RUN (nothing will be deleted)\n")
    printProjects(projects)
    
    if !projects.isEmpty && !config.dryRun {
        let totalSize = projects.reduce(0) { $0 + $1.size }
        print("Total space: \(formatBytes(totalSize))")
        print("\nTo clean these projects, use: devdug --clean -yy")
    }
} else {
    // Clean mode
    print("🧹 devdug - Cleanup Mode\n")
    printProjects(projects)
    
    if projects.isEmpty {
        print("No projects to clean.")
        exit(0)
    }
    
    let totalSize = projects.reduce(0) { $0 + $1.size }
    print("Total space to reclaim: \(formatBytes(totalSize))\n")
    
    // Require at least 2 confirmations for actual cleanup
    let requiredConfirmations = 2
    
    if config.confirmationCount < 1 {
        print("❌ Cleanup requires explicit confirmations.")
        print("Use: devdug --clean -yy (pass --yes flag twice)")
        print("Or:  devdug --clean --force (skip all confirmations - DANGEROUS)")
        exit(1)
    }
    
    if config.confirmationCount < requiredConfirmations {
        print("⚠️  Interactive confirmation required (pass -yy to skip)\n")
        
        // First confirmation
        if !requestConfirmation("Review complete. Are you sure you want to DELETE these projects?", confirmationNumber: 1) {
            print("Aborted.")
            exit(0)
        }
        
        // Second confirmation
        if !requestConfirmation("THIS CANNOT BE UNDONE. Delete these projects permanently?", confirmationNumber: 2) {
            print("Aborted.")
            exit(0)
        }
    }
    
    // All confirmations passed
    print("\n✅ Confirmed. Ready to clean.")
    print("(Actual cleanup not yet implemented)")
}
