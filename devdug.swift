#!/usr/bin/swift

import Foundation

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
                print("Unknown flag: \(arg)")
                printHelp()
                exit(1)
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

// MARK: - Project Discovery

func getStandardIDELocations() -> [String] {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    
    return [
        // IntelliJ variants
        "\(homeDir)/IdeaProjects",
        "\(homeDir)/RustroverProjects",
        "\(homeDir)/CLionProjects",
        "\(homeDir)/GolandProjects",
        "\(homeDir)/PyCharmProjects",
        "\(homeDir)/WebstormProjects",
        "\(homeDir)/AppCodeProjects",
        
        // Android
        "\(homeDir)/Android Studio Projects",
        
        // Eclipse
        "\(homeDir)/eclipse-workspace",
        "\(homeDir)/eclipse",
        
        // Root-level projects (common)
        "\(homeDir)/Projects",
        "\(homeDir)/Source",
        "\(homeDir)/Code",
        
        // VSCode workspace files typically scattered
        // No single location to scan
    ]
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

func detectProjectType(_ path: String) -> String? {
    let fm = FileManager.default
    
    // Check for Xcode project
    if fm.fileExists(atPath: "\(path)/.xcodeproj") {
        return "xcode"
    }
    
    // Check for IntelliJ
    if fm.fileExists(atPath: "\(path)/.idea") {
        return "intellij"
    }
    
    // Check for Cargo/Rust
    if fm.fileExists(atPath: "\(path)/Cargo.toml") {
        return "cargo"
    }
    
    // Check for npm
    if fm.fileExists(atPath: "\(path)/package.json") {
        return "npm"
    }
    
    // Check for Python
    if fm.fileExists(atPath: "\(path)/pyproject.toml") ||
       fm.fileExists(atPath: "\(path)/setup.py") {
        return "python"
    }
    
    // Check for Go
    if fm.fileExists(atPath: "\(path)/go.mod") {
        return "go"
    }
    
    // Check for Maven/Gradle
    if fm.fileExists(atPath: "\(path)/pom.xml") {
        return "maven"
    }
    if fm.fileExists(atPath: "\(path)/build.gradle") ||
       fm.fileExists(atPath: "\(path)/build.gradle.kts") {
        return "gradle"
    }
    
    // Check for Swift Package Manager
    if fm.fileExists(atPath: "\(path)/Package.swift") {
        return "swift-spm"
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

func discoverProjects(in locations: [String], verbose: Bool = false) -> [ProjectInfo] {
    let fm = FileManager.default
    var projects: [ProjectInfo] = []
    
    for location in locations {
        if !fm.fileExists(atPath: location) {
            if verbose {
                print("⊘ \(location) (not found)")
            }
            continue
        }
        
        do {
            let contents = try fm.contentsOfDirectory(atPath: location)
            
            for item in contents {
                let fullPath = "\(location)/\(item)"
                var isDir: ObjCBool = false
                
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir),
                      isDir.boolValue else {
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
                }
            }
        } catch {
            if verbose {
                print("Error scanning \(location): \(error)")
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

func requestConfirmation(_ message: String) -> Bool {
    print("\n\(message)")
    print("Continue? (yes/no): ", terminator: "")
    fflush(stdout)
    
    guard let response = readLine() else { return false }
    return response.lowercased().starts(with: "y")
}

// MARK: - Main

let config = parseArgs(CommandLine.arguments)

let locations = getStandardIDELocations()
let projects = discoverProjects(in: locations, verbose: config.verbose)

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
    
    if config.confirmationCount < 1 {
        print("❌ Cleanup requires at least one confirmation.")
        print("Use: devdug --clean -yy (or add --yes flags)")
        exit(1)
    }
    
    if config.confirmationCount < 2 {
        if !requestConfirmation("⚠️  DOUBLE-CHECK: Are you sure you want to delete these projects?") {
            print("Aborted.")
            exit(0)
        }
    }
    
    // Actually delete (TODO: implement when ready)
    print("✅ Ready to clean. (Cleanup not yet implemented)")
}
