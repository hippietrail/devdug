import Foundation

public class ProjectDiscovery {
    private let fileManager = FileManager.default

    public init() {}

    // MARK: - IDE Detection

    public func getInstalledIDEs() -> Set<String> {
        var installed: Set<String> = []

        let appPaths = [
            "/Applications/Xcode.app": "xcode",
            "/Applications/IntelliJ IDEA.app": "intellij-idea",
            "/Applications/RustRover.app": "rustrover",
            "/Applications/CLion.app": "clion",
            "/Applications/GoLand.app": "goland",
            "/Applications/PyCharm.app": "pycharm",
            "/Applications/WebStorm.app": "webstorm",
            "/Applications/AppCode.app": "appcode",
        ]

        for (path, id) in appPaths {
            if fileManager.fileExists(atPath: path) {
                installed.insert(id)
            }
        }

        return installed
    }

    // MARK: - Standard Locations

    public func getStandardIDELocations() -> [String] {
        let home = fileManager.homeDirectoryForCurrentUser.path
        
        return [
            "\(home)/IdeaProjects",
            "\(home)/RustroverProjects",
            "\(home)/eclipse-workspace",
            "\(home)/eclipse-ghidra-workspace",
            "\(home)/IdeaProjects",
            "\(home)/Projects",
            "/Users/Shared/Projects",
        ]
    }

    // MARK: - Project Discovery

    public func discoverProjects(in locations: [String], useBlocks: Bool = false) -> [ProjectInfo] {
         var projects: [ProjectInfo] = []
         
         for location in locations {
             guard fileManager.fileExists(atPath: location) else { continue }
             
             do {
                 let contents = try fileManager.contentsOfDirectory(atPath: location)
                 for item in contents {
                     let fullPath = (location as NSString).appendingPathComponent(item)
                     
                     if let projectType = detectProjectType(at: fullPath) {
                         do {
                             let size = useBlocks ? calculateBlockSize(fullPath) : calculateDirectorySize(fullPath)
                             let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                             let modified = (attrs[.modificationDate] as? Date) ?? Date()
                             
                             let (isGit, host, originURL) = detectGit(at: fullPath)
                             
                             let project = ProjectInfo(
                                 path: fullPath,
                                 name: item,
                                 type: projectType,
                                 size: size,
                                 lastModified: modified,
                                 isGitRepo: isGit,
                                 gitHost: host,
                                 gitOriginURL: originURL
                             )
                             projects.append(project)
                         } catch {
                             // Skip if we can't get attributes
                         }
                     }
                 }
             } catch {
                 // Skip locations we can't read
             }
         }
         
         return projects.sorted { $0.lastModified > $1.lastModified }
     }

    // MARK: - Home Directory Scanning

    public func scanHomeDirectory(useBlocks: Bool = false) -> [ProjectInfo] {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var projects: [ProjectInfo] = []
        
        // Scan top-level directories looking for indicators
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: home)
            
            for item in contents {
                guard !item.starts(with: ".") else { continue }
                
                let fullPath = (home as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }
                
                if let projectType = detectProjectType(at: fullPath) {
                     do {
                         let size = useBlocks ? calculateBlockSize(fullPath) : calculateDirectorySize(fullPath)
                         let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                         let modified = (attrs[.modificationDate] as? Date) ?? Date()
                         
                         let (isGit, host, originURL) = detectGit(at: fullPath)
                        
                        let project = ProjectInfo(
                            path: fullPath,
                            name: item,
                            type: projectType,
                            size: size,
                            lastModified: modified,
                            isGitRepo: isGit,
                            gitHost: host,
                            gitOriginURL: originURL
                        )
                        projects.append(project)
                    } catch {
                        // Skip if we can't get attributes
                    }
                }
            }
        } catch {
            // Skip if we can't read directory
        }
        
        return projects.sorted { $0.lastModified > $1.lastModified }
    }

    // MARK: - Git Detection

    public func detectGit(at path: String) -> (isGitRepo: Bool, host: GitHost, originURL: String?) {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        
        guard fileManager.fileExists(atPath: gitPath) else {
            return (false, .unknown, nil)
        }
        
        let originURL = parseGitOrigin(at: path)
        let host = detectGitHost(from: originURL)
        
        return (true, host, originURL)
    }

    private func parseGitOrigin(at path: String) -> String? {
        let configPath = (path as NSString).appendingPathComponent(".git/config")
        
        guard fileManager.fileExists(atPath: configPath),
              let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        
        // Parse git config for [remote "origin"] url = ...
        var inRemoteSection = false
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed == "[remote \"origin\"]" {
                inRemoteSection = true
                continue
            }
            
            if trimmed.starts(with: "[") && inRemoteSection {
                // Entered different section
                break
            }
            
            if inRemoteSection && trimmed.starts(with: "url =") {
                let urlPart = trimmed.dropFirst("url =".count).trimmingCharacters(in: .whitespaces)
                return String(urlPart)
            }
        }
        
        return nil
    }

    private func detectGitHost(from url: String?) -> GitHost {
        guard let url = url else { return .unknown }
        
        let lowerURL = url.lowercased()
        
        if lowerURL.contains("github.com") {
            return .github
        } else if lowerURL.contains("gitlab.com") {
            return .gitlab
        } else if lowerURL.contains("codeberg.org") {
            return .codeberg
        } else if lowerURL.contains("gitea") {
            return .gitea
        } else if let hostname = extractHostname(from: url) {
            return .custom(hostname: hostname)
        }
        
        return .unknown
    }

    private func extractHostname(from url: String) -> String? {
        // Handle both https://hostname/path and git@hostname:path formats
        if let atIndex = url.firstIndex(of: "@") {
            // git@hostname:path format
            let afterAt = url[url.index(after: atIndex)...]
            if let colonIndex = afterAt.firstIndex(of: ":") {
                return String(afterAt[..<colonIndex])
            }
        } else if url.contains("://") {
            // https://hostname/path format
            if let schemeEndIndex = url.range(of: "://")?.upperBound {
                let afterScheme = url[schemeEndIndex...]
                if let slashIndex = afterScheme.firstIndex(of: "/") {
                    return String(afterScheme[..<slashIndex])
                }
            }
        }
        return nil
    }

    // MARK: - Project Type Detection

    private func detectProjectType(at path: String) -> String? {
        let fileManager = FileManager.default
        
        // Check for specific multi-type projects first
        let tauriPath = (path as NSString).appendingPathComponent("src-tauri/tauri.conf.json")
        if fileManager.fileExists(atPath: tauriPath) {
            // Mark as tauri to distinguish from standalone cargo/npm projects
            // We'll add cargo and npm to the type list below
        }
        
        // Check for various project markers
        // Some projects can have multiple types (e.g., Tauri has both cargo and npm)
        let indicators: [(String, String)] = [
            ("src-tauri/tauri.conf.json", "tauri"),  // Tauri framework project
            ("Cargo.toml", "cargo"),
            ("package.json", "npm"),
            ("pyproject.toml", "python-poetry"),
            ("setup.py", "python-pip"),
            ("requirements.txt", "python-pip"),
            (".xcodeproj", "xcode"),
            (".xcworkspace", "xcode"),
            ("project.pbxproj", "xcode"),
            (".idea", "intellij-idea"),
            ("pom.xml", "maven"),
            ("build.gradle", "gradle"),
            ("build.gradle.kts", "gradle"),
            ("CMakeLists.txt", "cmake"),
            ("Makefile", "make"),
            ("go.mod", "go"),
            ("Package.swift", "swift-spm"),
            ("build.zig", "zig"),
            (".git", "git-repo"),
        ]
        
        // Detect all applicable project types
        var detectedTypes: [String] = []
        for (marker, type) in indicators {
            let markerPath = (path as NSString).appendingPathComponent(marker)
            if fileManager.fileExists(atPath: markerPath) {
                // Avoid duplicates (e.g., xcode can match both .xcodeproj and .xcworkspace)
                if !detectedTypes.contains(type) {
                    detectedTypes.append(type)
                }
            }
        }
        
        // Return comma-separated list of types (primary type first)
        // Primary type determination: preferred types in order of priority
        // Multi-type projects (like tauri) appear first, followed by primary language/framework
        let typeOrder = ["tauri", "cargo", "npm", "go", "python-poetry", "python-pip", "xcode", 
                        "swift-spm", "gradle", "maven", "cmake", "make", "zig",
                        "intellij-idea", "git-repo"]
        
        let sorted = detectedTypes.sorted { type1, type2 in
            let idx1 = typeOrder.firstIndex(of: type1) ?? typeOrder.count
            let idx2 = typeOrder.firstIndex(of: type2) ?? typeOrder.count
            return idx1 < idx2
        }
        
        return sorted.isEmpty ? nil : sorted.joined(separator: ", ")
    }
}

// MARK: - Utility Functions

public func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    
    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    
    // NOTE: Cannot use String(format: "%.1f %s", value, units[unitIndex])
    // because %s expects const char* (C string), not a Swift String.
    // This caused segfault when formatter tried to dereference Swift String
    // as a C pointer. Use string interpolation instead.
    let formatted = String(format: "%.1f", value)
    return "\(formatted) \(units[unitIndex])"
}

// MARK: - Size Calculation (Recursive)

/// Recursively calculates the total size of all files in a directory.
/// Uses Apple FileManager APIs which properly handle firmlinks.
/// Does NOT count directory entries themselves, only regular files.
private func calculateDirectorySize(_ path: String) -> UInt64 {
    let fm = FileManager.default
    let url = URL(fileURLWithPath: path)
    
    let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    
    // Use enumerator for recursive traversal. Apple APIs properly handle firmlinks.
    // Do NOT skip hidden files or packages - .idea/, .build/, .git/, node_modules/ are largest!
    let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: resourceKeys,
        options: []
    )
    
    var totalSize: UInt64 = 0
    
    while let fileURL = enumerator?.nextObject() as? URL {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            
            // Only count regular files, not directories or symlinks
            if resourceValues.isRegularFile == true {
                if let fileSize = resourceValues.fileSize {
                    totalSize += UInt64(fileSize)
                }
            }
        } catch {
            // Continue on per-file errors (permission issues, etc.)
            continue
        }
    }
    
    return totalSize
}

/// Calculates actual disk blocks used (like `du -sk`).
/// Returns size in bytes (1 block = 512 bytes, but du -sk reports in KB).
/// More realistic for cleanup planning as it accounts for block allocation.
func calculateBlockSize(_ path: String) -> UInt64 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
    process.arguments = ["-sk", path]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let components = output.split(separator: "\t")
            if let firstComponent = components.first,
               let kb = UInt64(firstComponent.trimmingCharacters(in: .whitespaces)) {
                return kb * 1024 // Convert KB to bytes
            }
        }
    } catch {
        // Fallback to file size calculation
        return calculateDirectorySize(path)
    }
    
    return calculateDirectorySize(path)
}
