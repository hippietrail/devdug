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
    static let red = "\u{1B}[31m"
    
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
    
    func buildStatusLine() -> String {
        let counts = projectCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " | ")
        
        let totalProjects = projectCounts.values.reduce(0, +)
        return "Total: \(totalProjects) | \(counts)"
    }
    
    func updateStatus() {
        // Don't update during discovery - avoids terminal scrolling issues
    }
    
    func setup() {
        isSetup = true
    }
    
    func cleanup() {
        // Print final status after discovery completes
        if !projectCounts.isEmpty {
            print("\n\(ANSI.dim)⧏ \(buildStatusLine())\(ANSI.reset)")
        }
        isSetup = false
    }
    
    func printMessage(_ message: String) {
        print(message)
        fflush(stdout)
    }
}

// MARK: - Project Type Emojis

let projectEmojis: [String: String] = [
    "cargo": "🦀",
    "npm": "📦",
    "python-pip": "🐍",
    "python-poetry": "🐍",
    "python-setuptools": "🐍",
    "gradle": "☕️",
    "maven": "☕️",
    "swift-spm": "🍎",
    "xcode": "🍎",
    "cmake": "📐",
    "make": "🔨",
    "go": "🐹",
    "intellij-idea": "💡",
    "android-studio": "🤖",
    "rustrover": "🦀",
    "clion": "⚙️",
    "goland": "🐹",
    "pycharm": "🐍",
    "webstorm": "⚡️",
    "appcode": "🍎",
    "visual-studio": "🔷",
    "eclipse-workspace": "🌀",
    "zig": "⚡️",
    "git-repo": "🔗",
    "generic": "📁",
]

func projectEmoji(_ type: String) -> String {
    return projectEmojis[type] ?? "📦"
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

struct CleanupAction {
    let type: ActionType
    let description: String
    let estimatedSize: UInt64? // nil if unknown
    
    enum ActionType {
        case safeCommand      // green: cargo clean, npm ci, etc.
        case tentativeCommand // yellow: make clean (uncertain)
        case pathDelete       // red: target/, node_modules/, *.o
    }
    
    func colorize() -> String {
        let colorCode: String
        switch type {
        case .safeCommand:
            colorCode = ANSI.green
        case .tentativeCommand:
            colorCode = ANSI.yellow
        case .pathDelete:
            colorCode = ANSI.red
        }
        return "\(colorCode)\(description)\(ANSI.reset)"
    }
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
        "/Applications/IntelliJ IDEA.app": "intellij-idea",
        "/Applications/RustRover.app": "rustrover",
        "/Applications/CLion.app": "clion",
        "/Applications/GoLand.app": "goland",
        "/Applications/PyCharm.app": "pycharm",
        "/Applications/WebStorm.app": "webstorm",
        "/Applications/AppCode.app": "appcode",
        "/Applications/Android Studio.app": "android-studio",
        "/Applications/Visual Studio.app": "visual-studio",
    ]
    
    // Eclipse and other IDEs often installed outside /Applications
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let altPaths = [
        "/opt/eclipse/Eclipse.app": "eclipse",
        "/opt/eclipse": "eclipse",
    ]
    
    for (path, name) in appPaths {
        if fm.fileExists(atPath: path) {
            installed.insert(name)
        }
    }
    
    for (path, name) in altPaths {
        if fm.fileExists(atPath: path) {
            installed.insert(name)
        }
    }
    
    // Eclipse in ~/eclipse - check for any versioned subdirectory with Eclipse.app
    // (Eclipse updates install in versioned dirs like java-2024-09, java-2025-12, etc)
    let eclipseBaseDir = "\(homeDir)/eclipse"
    if fm.fileExists(atPath: eclipseBaseDir) {
        if let contents = try? fm.contentsOfDirectory(atPath: eclipseBaseDir) {
            for subdir in contents {
                let appPath = "\(eclipseBaseDir)/\(subdir)/Eclipse.app"
                if fm.fileExists(atPath: appPath) {
                    installed.insert("eclipse")
                    break
                }
            }
        }
    }
    
    return installed
}

func getStandardIDELocations() -> [(path: String, ide: String)] {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var locations: [(String, String)] = []
    
    let ideMap: [(path: String, ide: String)] = [
        // IntelliJ variants
        ("\(homeDir)/IdeaProjects", "intellij-idea"),
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
        
        // Visual Studio for Mac
        ("\(homeDir)/Projects", "visual-studio"),
        
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
    
    // Breadth-first scan up to 3 levels deep
    func scanLevel(_ dir: String, depth: Int) {
        guard depth <= 3 else { return }
        
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { return }
        
        for item in contents {
            let fullPath = "\(dir)/\(item)"
            var isDir: ObjCBool = false
            
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir),
                  isDir.boolValue else {
                continue
            }
            
            // Skip hidden and explicitly excluded dirs
            if item.starts(with: ".") || skipDirs.contains(item) {
                continue
            }
            
            // Try to detect project at this level
            if let type = detectProjectType(fullPath) {
                let size = getDirectorySize(fullPath)
                let attributes = try? fm.attributesOfItem(atPath: fullPath)
                let modDate = (attributes?[.modificationDate] as? Date) ?? Date()
                
                projects.append(ProjectInfo(
                    path: fullPath,
                    name: item,
                    type: type,
                    size: size,
                    lastModified: modDate
                ))
                
                if verbose {
                    let emoji = projectEmoji(type)
                    let msg = "✓ \(emoji) Found \(item) (\(type)) in ~"
                    ui?.printMessage(msg) ?? print(msg)
                }
                
                if let ui = ui {
                    ui.recordProject(type: type)
                    ui.updateStatus()
                }
                
                // Don't recurse into found projects
                continue
            }
            
            // No project found, recurse to next level
            scanLevel(fullPath, depth: depth + 1)
        }
    }
    
    scanLevel(homeDir, depth: 1)
    return projects
}

func getCleanupActions(for projectType: String, at projectPath: String) -> [CleanupAction] {
    let fm = FileManager.default
    var actions: [CleanupAction] = []
    
    switch projectType {
    case "cargo":
        actions.append(CleanupAction(type: .safeCommand, description: "cargo clean", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "target/", estimatedSize: nil))
        
    case "npm":
        actions.append(CleanupAction(type: .safeCommand, description: "npm ci --prefer-offline", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "node_modules/", estimatedSize: nil))
        
    case "gradle":
        actions.append(CleanupAction(type: .safeCommand, description: "./gradlew clean", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "build/", estimatedSize: nil))
        
    case "swift-spm":
        actions.append(CleanupAction(type: .pathDelete, description: ".build/", estimatedSize: nil))
        
    case "python-pip", "python-poetry", "python-setuptools":
        actions.append(CleanupAction(type: .pathDelete, description: "__pycache__/", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "dist/", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "build/", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "*.egg-info/", estimatedSize: nil))
        
    case "make":
        let makefilePath = "\(projectPath)/Makefile"
        if fm.fileExists(atPath: makefilePath) {
            actions.append(CleanupAction(type: .tentativeCommand, description: "make clean (if target exists)", estimatedSize: nil))
        }
        actions.append(CleanupAction(type: .pathDelete, description: "build/", estimatedSize: nil))
        
    case "cmake":
        actions.append(CleanupAction(type: .tentativeCommand, description: "make clean (if CMakeLists.txt)", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "cmake-build-debug/", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "cmake-build-release/", estimatedSize: nil))
        
    case "intellij-idea":
        actions.append(CleanupAction(type: .pathDelete, description: ".idea/cache/", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: ".idea/caches/", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: ".idea/shelf/", estimatedSize: nil))
        
    case "eclipse-workspace":
        actions.append(CleanupAction(type: .pathDelete, description: ".recommenders/", estimatedSize: nil))
        
    case "xcode":
        actions.append(CleanupAction(type: .pathDelete, description: "~/Library/Developer/Xcode/DerivedData/<ProjectName>-*/", estimatedSize: nil))
        
    case "go":
        if fm.fileExists(atPath: "\(projectPath)/vendor") {
            actions.append(CleanupAction(type: .tentativeCommand, description: "rm -rf vendor/", estimatedSize: nil))
        }
        
    case "git-repo":
        actions.append(CleanupAction(type: .safeCommand, description: "git gc --aggressive (optimize, don't delete)", estimatedSize: nil))
        
    default:
        // No known cleanup
        break
    }
    
    return actions
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
        return "intellij-idea"
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
    
    do {
        let attributes = try fm.attributesOfItem(atPath: path)
        return attributes[.size] as? UInt64 ?? 0
    } catch {
        return 0
    }
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
                        let emoji = projectEmoji(type)
                        let msg = "✓ \(emoji) Found \(item) (\(type)) in \(ide)"
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
        let emoji = projectEmoji(project.type)
        print("  \(emoji) \(project.name)")
        print("     Type: \(project.type) | Size: \(sizeStr) | Modified: \(dateStr)")
        print("     Path: \(project.path)\n")
    }
}

func printCleanupStrategy(_ projects: [ProjectInfo]) {
    if projects.isEmpty {
        print("No projects to clean.")
        return
    }
    
    print("\(ANSI.bold)CLEANUP STRATEGY\(ANSI.reset)\n")
    print("Review what will be cleaned for each project:\n")
    
    var totalEstimatedSize: UInt64 = 0
    
    for project in projects {
        let emoji = projectEmoji(project.type)
        let sizeStr = formatBytes(project.size)
        
        print("\(ANSI.bold)\(emoji) \(project.name)\(ANSI.reset) (\(project.type))")
        print("  \(ANSI.dim)Size: \(sizeStr) | Path: \(project.path)\(ANSI.reset)")
        
        let actions = getCleanupActions(for: project.type, at: project.path)
        
        if actions.isEmpty {
            print("  \(ANSI.dim)No automatic cleanup defined\(ANSI.reset)")
        } else {
            for action in actions {
                let colored = action.colorize()
                print("  \(colored)")
            }
            // Rough estimate: assume we can reclaim most of project size via cleanup
            totalEstimatedSize += project.size
        }
        
        print()
    }
    
    print("\(ANSI.bold)Estimated space to reclaim: \(formatBytes(totalEstimatedSize))\(ANSI.reset)")
    print("\n\(ANSI.yellow)Yellow actions (⚠️  tentative) require manual verification.\(ANSI.reset)")
    print("\(ANSI.red)Red paths will be permanently deleted.\(ANSI.reset)")
    print("\(ANSI.green)Green commands are safe to run.\(ANSI.reset)\n")
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
    ui?.printMessage("🔍 Checking for IDE installations in /Applications...\n") ?? print("🔍 Checking for IDE installations in /Applications...\n")
    let installed = getInstalledIDEs()
    if installed.isEmpty {
        ui?.printMessage("No IDE applications found (scanning all standard project locations anyway)\n") ?? print("No IDE applications found (scanning all standard project locations anyway)\n")
    } else {
        ui?.printMessage("IDE apps found: \(installed.sorted().joined(separator: ", "))\n") ?? print("IDE apps found: \(installed.sorted().joined(separator: ", "))\n")
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

if config.listOnly {
    // Minimal list mode - just projects, no strategy
    print("🔍 devdug - Project Discovery\n")
    print("Mode: DRY-RUN (nothing will be deleted)\n")
    printProjects(projects)
} else if config.dryRun {
    // Default dry-run mode - show discovery + strategy
    print("🔍 devdug - Project Discovery & Cleanup Plan\n")
    print("Mode: DRY-RUN (nothing will be deleted)\n")
    
    if projects.isEmpty {
        print("No projects found.")
        exit(0)
    }
    
    printProjects(projects)
    print("\n" + String(repeating: "=", count: 60) + "\n")
    
    // Show strategy preview
    printCleanupStrategy(projects)
    
    let totalSize = projects.reduce(0) { $0 + $1.size }
    print("Total disk space: \(formatBytes(totalSize))")
    print("\nTo actually clean these projects, use: devdug --clean -yy")
} else {
    // Clean mode - requires manual confirmation before execution
    print("🧹 devdug - Cleanup Mode\n")
    
    // Reject any attempt to skip confirmations
    if config.confirmationCount > 0 {
        print("⛔️  ⛔️  ⛔️  CLEANUP CANNOT BE AUTOMATED ⛔️  ⛔️  ⛔️\n")
        print("Flags like -y/--yes and --force are DISABLED for cleanup.")
        print("This is intentional - you must manually review and confirm.")
        print("\nReason: Lost Android Studio projects once? So did we.")
        print("We're not letting that happen again.\n")
        print("Required workflow:")
        print("  1. Run: devdug (no flags)")
        print("  2. Review the cleanup plan")
        print("  3. Run: devdug --clean")
        print("  4. Read each prompt carefully and type 'yes'\n")
        exit(1)
    }
    
    if projects.isEmpty {
        print("No projects to clean.")
        exit(0)
    }
    
    // Show discovery
    printProjects(projects)
    print("\n" + String(repeating: "=", count: 60) + "\n")
    
    // Show strategy preview for each project
    printCleanupStrategy(projects)
    
    // Require interactive confirmations (always - no way to skip)
    print("⚠️  Manual confirmation required (cannot be skipped)\n")
    
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
    
    // All confirmations passed
    print("\n✅ Confirmed. Ready to clean.")
    print("(Actual cleanup not yet implemented)")
}
