import Foundation
import Darwin
import DevdugCore

// MARK: - Terminal Utilities

// VERIFIED: ioctl(TIOCGWINSZ) works reliably on macOS
// Tested and working on both iTerm2 and Terminal.app
// Returns actual terminal width in real-time
//
// ALTERNATIVE (also verified): COLUMNS environment variable
// Works on both iTerm2 and Terminal.app
// Both terminals automatically update COLUMNS env var on resize
// Simpler but less reliable - depends on shell setting COLUMNS
//
// NOTE: ANSI escape sequence method exists (CSI 18 t query)
// but requires reading/parsing terminal response - more complex
// ioctl is simpler and more direct for our use case
func getTerminalWidth() -> Int {
    // Primary method: ioctl(TIOCGWINSZ) - most reliable
    var size = winsize()
    let resultStdout = Darwin.ioctl(fileno(stdout), UInt(TIOCGWINSZ), &size)
    if resultStdout != 0 || size.ws_col == 0 {
        _ = Darwin.ioctl(fileno(stderr), UInt(TIOCGWINSZ), &size)
    }
    if Int(size.ws_col) > 0 {
        return Int(size.ws_col)
    }
    // Fallback: COLUMNS environment variable
    if let columnsStr = ProcessInfo.processInfo.environment["COLUMNS"],
       let width = Int(columnsStr),
       width > 0 {
        return width
    }
    // Final fallback: 80
    return 80
}

// MARK: - ANSI Terminal Control

struct ANSI {
    static let reset = "\u{1B}[0m"
    static let bold = "\u{1B}[1m"
    static let dim = "\u{1B}[2m"
    static let cyan = "\u{1B}[36m"
    static let green = "\u{1B}[32m"
    static let yellow = "\u{1B}[33m"
    static let red = "\u{1B}[31m"
    
    static let saveCursor = "\u{1B}[s"
    static let restoreCursor = "\u{1B}[u"
    static func moveTo(row: Int, col: Int) -> String {
        return "\u{1B}[\(row);\(col)H"
    }
    static func clearLine() -> String {
        return "\u{1B}[K"
    }
    
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

// MARK: - Argument Parser

func parseArgs(_ args: [String]) -> Config {
    var dryRun = true
    var listOnly = false
    var verbose = false
    var confirmations = 0
    var useBlocks = false
    
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
        case "--blocks":
            useBlocks = true
        case "--help", "-h":
            printHelp()
            exit(0)
        default:
            if arg.starts(with: "-") {
                if arg.starts(with: "--") {
                    print("Unknown flag: \(arg)")
                    printHelp()
                    exit(1)
                }
                
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
        confirmationCount: confirmations,
        useBlocks: useBlocks
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
        --blocks            Show actual disk usage (du -sk) instead of raw file sizes
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

// MARK: - Cleanup Actions

func getCleanupActions(for projectType: String, at projectPath: String) -> [CleanupAction] {
    var actions: [CleanupAction] = []
    
    // Handle comma-separated types (e.g., "tauri, cargo, npm")
    let types = projectType.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    
    // Process each type to collect all applicable cleanup actions
    for type in types {
        addCleanupActionsForType(type, to: &actions)
    }
    
    return actions
}

private func addCleanupActionsForType(_ projectType: String, to actions: inout [CleanupAction]) {
    switch projectType {
    case "tauri":
        // Tauri projects have both Rust (cargo) and Node (npm) components
        // Add tauri-specific cleanup
        break  // Tauri cleanup is handled by cargo and npm sections
        
    case "cargo":
        actions.append(CleanupAction(type: .safeCommand, description: "cargo clean", explanation: "Removes compiled artifacts (target/). Safe to run anytime - rebuilds from source on next build.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "target/", explanation: "Build output, compiled binaries, dependencies (typically 200MB-1GB per project)", estimatedSize: nil))
        
    case "npm":
        actions.append(CleanupAction(type: .safeCommand, description: "npm ci --prefer-offline", explanation: "Reinstalls dependencies from package-lock.json offline. Safe - you have the lock file.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "node_modules/", explanation: "Downloaded npm packages (typically 100MB-1.3GB per project). Regenerate with npm ci.", estimatedSize: nil))
        
    case "gradle":
        actions.append(CleanupAction(type: .safeCommand, description: "./gradlew clean", explanation: "Gradle's standard clean target. Removes build artifacts.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "build/", explanation: "Compiled classes, JARs, and outputs. Gradle rebuilds on next run.", estimatedSize: nil))
        
    case "swift-spm":
        actions.append(CleanupAction(type: .pathDelete, description: ".build/", explanation: "Swift compiled artifacts (typically 50-100MB). Rebuilds automatically.", estimatedSize: nil))
        
    case "python-pip", "python-poetry", "python-setuptools":
        actions.append(CleanupAction(type: .pathDelete, description: "__pycache__/", explanation: "Python bytecode cache. Regenerated on import.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: ".venv/", explanation: "Virtual environment. Recreate with: python -m venv .venv", estimatedSize: nil))
        
    case "xcode", "appcode":
        actions.append(CleanupAction(type: .pathDelete, description: "Build/", explanation: "Xcode build artifacts. Will be rebuilt on next build.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: ".xcarchive/", explanation: "Old archived builds. Safe to delete.", estimatedSize: nil))
        
    case "intellij-idea", "pycharm", "webstorm", "clion", "goland", "rustrover":
        actions.append(CleanupAction(type: .pathDelete, description: ".idea/", explanation: "IDE settings and caches. Will be recreated on next open.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "out/", explanation: "Compiled output. Will be rebuilt.", estimatedSize: nil))
        
    case "android-studio":
        actions.append(CleanupAction(type: .pathDelete, description: "build/", explanation: "Android build outputs.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: ".idea/", explanation: "IDE caches (recreated on next open).", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: ".gradle/", explanation: "Gradle cache for this project.", estimatedSize: nil))
        
    case "zig":
        actions.append(CleanupAction(type: .pathDelete, description: ".zig-cache/", explanation: "Zig build cache and compilation artifacts. Regenerated on next build.", estimatedSize: nil))
        actions.append(CleanupAction(type: .pathDelete, description: "zig-out/", explanation: "Zig build output directory. Regenerated on next build.", estimatedSize: nil))
        
    case "cmake":
        actions.append(CleanupAction(type: .tentativeCommand, description: "rm -rf build/", explanation: "CMake build directory. Will be recreated by cmake --build (if you save your cmake cache).", estimatedSize: nil))
        
    case "make":
        actions.append(CleanupAction(type: .tentativeCommand, description: "make clean", explanation: "Run make clean if defined. If not defined, may have no effect.", estimatedSize: nil))
        
    case "git-repo":
         actions.append(CleanupAction(type: .tentativeCommand, description: "git gc", explanation: "Garbage collect git objects. Safe but might take time.", estimatedSize: nil))
         
     default:
         break  // Unknown type, skip
     }
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

func printCleanupStrategy(_ projects: [ProjectInfo], verbose: Bool = false) {
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
                let colorCode: String
                switch action.type {
                case .safeCommand:
                    colorCode = ANSI.green
                case .tentativeCommand:
                    colorCode = ANSI.yellow
                case .pathDelete:
                    colorCode = ANSI.red
                }
                let colored = "\(colorCode)\(action.description)\(ANSI.reset)"
                print("  \(colored)")
                if verbose, let explanation = action.explanation {
                    print("    \(ANSI.dim)→ \(explanation)\(ANSI.reset)")
                }
            }
            totalEstimatedSize += project.size
        }
        
        print()
    }
    
    print("\(ANSI.bold)Estimated space to reclaim: \(formatBytes(totalEstimatedSize))\(ANSI.reset)")
    
    let topProjects = projects.sorted { $0.size > $1.size }.prefix(3)
    if !topProjects.isEmpty {
        print("\n\(ANSI.bold)💰 Biggest disk space savings:\(ANSI.reset)")
        for project in topProjects {
            let emoji = projectEmoji(project.type)
            let sizeStr = formatBytes(project.size)
            print("  \(emoji) \(project.name) (\(project.type)): \(sizeStr)")
        }
    }
    
    print("\n\(ANSI.yellow)Yellow actions (⚠️  tentative) require manual verification.\(ANSI.reset)")
    print("\(ANSI.red)Red paths will be permanently deleted.\(ANSI.reset)")
    print("\(ANSI.green)Green commands are safe to run.\(ANSI.reset)")
    
    let usedTypes = Set(projects.map { $0.type }).sorted()
    if !usedTypes.isEmpty {
        print()
        let legendItems = usedTypes.map { type -> String in
            let emoji = projectEmoji(type)
            return "\(emoji) \(type)"
        }
        
        var currentLine = ""
        var lines: [String] = []
        let terminalWidth = getTerminalWidth()
        let padding = 2
        
        for item in legendItems {
            let testLine = currentLine.isEmpty ? item : currentLine + "  " + item
            let emojiCount = testLine.filter { String($0).rangeOfCharacter(from: .symbols) != nil }.count
            let displayWidth = testLine.count + emojiCount + padding
            
            if displayWidth <= terminalWidth {
                currentLine = testLine
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                }
                currentLine = item
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        for line in lines {
            print("\(ANSI.dim)\(line)\(ANSI.reset)")
        }
    }
    print()
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
let ui = config.verbose ? TerminalUI() : nil
ui?.setup()

let discovery = ProjectDiscovery()

if config.verbose {
    ui?.printMessage("🔍 Checking for IDE installations in /Applications...\n") ?? print("🔍 Checking for IDE installations in /Applications...\n")
    let installed = discovery.getInstalledIDEs()
    if installed.isEmpty {
        ui?.printMessage("No IDE applications found (scanning all standard project locations anyway)\n") ?? print("No IDE applications found (scanning all standard project locations anyway)\n")
    } else {
        ui?.printMessage("IDE apps found: \(installed.sorted().joined(separator: ", "))\n") ?? print("IDE apps found: \(installed.sorted().joined(separator: ", "))\n")
    }
}

let locations = discovery.getStandardIDELocations()
var projects = discovery.discoverProjects(in: locations, useBlocks: config.useBlocks)

if config.verbose {
    ui?.printMessage("\n🏠 Scanning home directory for scattered projects...\n") ?? print("\n🏠 Scanning home directory for scattered projects...\n")
}
let homeProjects = discovery.scanHomeDirectory(useBlocks: config.useBlocks)
projects.append(contentsOf: homeProjects)

ui?.cleanup()

// Dedup by path
projects = Array(Set(projects.map { $0.path })).compactMap { path in
    projects.first { $0.path == path }
}

if config.listOnly {
    print("🔍 devdug - Project Discovery\n")
    print("Mode: DRY-RUN (nothing will be deleted)\n")
    printProjects(projects)
} else if config.dryRun {
    print("🔍 devdug - Project Discovery & Cleanup Plan\n")
    print("Mode: DRY-RUN (nothing will be deleted)\n")
    
    if projects.isEmpty {
        print("No projects found.")
        exit(0)
    }
    
    printProjects(projects)
    print("\n" + String(repeating: "=", count: 60) + "\n")
    printCleanupStrategy(projects, verbose: config.verbose)
    
    let totalSize = projects.reduce(0) { $0 + $1.size }
    print("Total disk space: \(formatBytes(totalSize))")
    print("\nTo actually clean these projects, use: devdug --clean")
} else {
    print("🧹 devdug - Cleanup Mode\n")
    
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
    
    printProjects(projects)
    print("\n" + String(repeating: "=", count: 60) + "\n")
    printCleanupStrategy(projects, verbose: config.verbose)
    
    print("⚠️  Manual confirmation required (cannot be skipped)\n")
    
    if !requestConfirmation("Review complete. Are you sure you want to DELETE these projects?", confirmationNumber: 1) {
        print("Aborted.")
        exit(0)
    }
    
    if !requestConfirmation("THIS CANNOT BE UNDONE. Delete these projects permanently?", confirmationNumber: 2) {
        print("Aborted.")
        exit(0)
    }
    
    print("\n✅ Confirmed. Ready to clean.")
    print("(Actual cleanup not yet implemented)")
}
