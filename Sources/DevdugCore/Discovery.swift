import Foundation

// MARK: - Project Cache Manager
/// Manages persistence of discovered projects to ~/.devdug/projects-cache.json
/// Enables instant second+ runs without rescanning everything.
/// Cache is invalidated after 24 hours or on explicit refresh.
class ProjectCacheManager {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let cacheFileURL: URL
    
    init() {
        let home = fileManager.homeDirectoryForCurrentUser
        self.cacheDirectory = home.appendingPathComponent(".devdug")
        self.cacheFileURL = cacheDirectory.appendingPathComponent("projects-cache.json")
        
        // Create .devdug directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Load cached projects. Returns (projects, cacheAge in seconds) or nil if cache doesn't exist or is stale
    func loadCache() -> (projects: [ProjectInfo], ageSeconds: TimeInterval)? {
        guard fileManager.fileExists(atPath: cacheFileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let projects = try JSONDecoder().decode([ProjectInfo].self, from: data)
            
            // Check cache age
            let attrs = try fileManager.attributesOfItem(atPath: cacheFileURL.path)
            let modDate = (attrs[.modificationDate] as? Date) ?? Date.distantPast
            let ageSeconds = Date().timeIntervalSince(modDate)
            
            // Cache is valid for 24 hours (86400 seconds)
            if ageSeconds < 86400 {
                return (projects, ageSeconds)
            }
            return nil
        } catch {
            // Cache corrupted or unreadable, treat as miss
            return nil
        }
    }
    
    /// Save projects to cache
    func saveCache(_ projects: [ProjectInfo]) {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: cacheFileURL)
        } catch {
            // Silently fail cache save; discovery still succeeds
            print("⚠️  Failed to save project cache: \(error)")
        }
    }
    
    /// Clear cache (used for explicit refresh)
    func clearCache() {
        try? fileManager.removeItem(at: cacheFileURL)
    }
}

public class ProjectDiscovery {
    private let fileManager = FileManager.default
    private let cacheManager = ProjectCacheManager()

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

    // MARK: - Progressive Discovery with Phases and Caching
    
    /// Discover projects in phases with callbacks. Enables responsive UI by showing IDE projects
    /// immediately (300ms) while home directory scan (11.4s) continues in background.
    /// 
    /// PERFORMANCE METRICS (Phase A, Session 2):
    /// - First run (no cache):
    ///   * IDE projects: 39 projects @ ~300ms → Show to user immediately
    ///   * Home scan: 92 projects @ ~11.4s → Update display with 114 total
    ///   * Perceived startup: Shows projects in 300ms instead of 11.7s (35x faster)
    /// - Second+ run (with cache):
    ///   * Cache load: 114 projects @ ~50-100ms → Show to user immediately
    ///   * Background rescan: async, non-blocking
    ///   * Perceived startup: Instant (~100ms instead of 11.7s, 100x faster)
    /// 
    /// ARCHITECTURE:
    /// - Cache stored in ~/.devdug/projects-cache.json (auto-created)
    /// - Cache valid for 24 hours; expires after that
    /// - Phase 1 (cache) runs synchronously but is instant
    /// - Phases 2-4 run sequentially (IDE scan first, home scan second) for responsiveness
    /// - Callbacks allow UI to update at two critical points (IDE ready + all ready)
    /// 
    /// PHASES:
    /// 1. Load cache (instant, ~0-100ms) - if exists and valid
    ///    - On hit: return cached projects, launch async rescan in background
    ///    - On miss: proceed to phases 2-4
    /// 2. Discover IDE projects (fast, ~300ms) - only 7 standard locations
    ///    - Fire onIDEProjectsFound callback → UI shows 39 projects immediately
    /// 3. Scan home directory (slow, ~11.4s) - recursive traversal of ~/
    ///    - This is the major bottleneck (97% of time)
    ///    - See Phase B (ddg-u6f, ddg-4co) for optimization roadmap
    ///    - TODO: Profile with Instruments to find exact cause (I/O vs CPU vs recursion)
    /// 4. Merge, dedupe, sort, cache (fast, <50ms)
    ///    - Fire onAllProjectsFound callback → UI shows 114 projects
    ///    - Save to cache for next run (~100x speedup on run 2)
    /// 
    /// CALLBACKS:
    /// - onIDEProjectsFound: Called after phase 2, with 39 IDE projects ready for display
    /// - onAllProjectsFound: Called after phase 4, with 114 merged/deduped/sorted projects
    /// - Both invoked on the calling thread (typically background for GUI)
    public func discoverProjectsProgressively(
        useBlocks: Bool = false,
        onIDEProjectsFound: (([ProjectInfo]) -> Void)? = nil,
        onAllProjectsFound: (([ProjectInfo]) -> Void)? = nil
    ) -> [ProjectInfo] {
        let timer = DebugTimer("🚀 [discovery] ")
        
        // Phase 1: Try to load from cache
        // If cache exists and is <24h old, return immediately and rescan in background.
        // This enables "instant" startup on runs 2+ (11.7s → ~100ms).
        if let cached = cacheManager.loadCache() {
            timer.elapsed("Loaded \(cached.projects.count) projects from cache (age: \(Int(cached.ageSeconds))s)")
            
            // Invoke callbacks immediately with cached data for UI consistency
            // Even though this is "old" data, it's better than blank screen
            onIDEProjectsFound?(cached.projects.filter { $0.type.contains("xcode") || $0.type.contains("intellij") })
            onAllProjectsFound?(cached.projects)
            
            // Launch background async rescan (non-blocking, fire and forget)
            // If cache is old (>1h), home scan might find new projects
            // New cache will be written on next fresh discovery
            DispatchQueue.global(qos: .background).async { [weak self] in
                let _ = self?.scanHomeDirectory(useBlocks: useBlocks)
                // TODO (Phase B): Implement cache invalidation strategy
                // Options: (1) update cache immediately after rescan, (2) only update if >X new projects found
            }
            
            return cached.projects
        }
        
        // Phase 2: Discover IDE projects (fast, ~300ms)
        // Scans only 7 standard locations (IdeaProjects/, RustroverProjects/, Projects/, etc.)
        // Returns ~39 projects. This is fast because:
        // - Limited to top-level directories
        // - Each directory is small-ish
        // - No recursive home directory scan yet
        let standardLocations = getStandardIDELocations()
        let ideProjects = discoverProjects(in: standardLocations, useBlocks: useBlocks)
        timer.elapsed("discoverProjects() returned \(ideProjects.count) IDE projects")
        
        // Fire IDE callback so UI can show something at 300ms
        // Users see projects quickly, can start interacting while home scan continues
        onIDEProjectsFound?(ideProjects)
        
        // Phase 3: Scan home directory (slow, ~11.4s)
        // This is the critical bottleneck consuming 97% of startup time.
        // Recursive filesystem traversal of entire ~/. Returns ~92 projects.
        // 
        // PERFORMANCE ANALYSIS NEEDED (Phase B, ddg-4co):
        // - Is scanHomeDirectory I/O-bound or CPU-bound?
        // - How many filesystem calls? (likely 1000s)
        // - Where are the hot spots? (Use Instruments: System Trace, File Activity, Time Profiler)
        // - Is it the recursive enumeration? Pattern matching? Directory metadata?
        // 
        // After profiling, Phase B optimizations (ddg-u6f):
        // - Option 1: Limit recursion depth (2-3 levels, skip .*, node_modules, .cargo)
        // - Option 2: Use FSEvents for incremental updates (cache-aware)
        // - Option 3: Parallelize scanning across multiple directories
        // - Option 4: Rewrite to use different traversal method
        let homeProjects = scanHomeDirectory(useBlocks: useBlocks)
        timer.elapsed("scanHomeDirectory() returned \(homeProjects.count) home projects")
        
        // Phase 4: Merge, dedupe, sort
        var allProjects = homeProjects + ideProjects
        
        // Remove duplicates by path (some projects might appear in both IDE locations and home scan)
        var seenPaths = Set<String>()
        allProjects = allProjects.filter { project in
            guard !seenPaths.contains(project.path) else { return false }
            seenPaths.insert(project.path)
            return true
        }
        timer.elapsed("Removed duplicates: \(allProjects.count) unique projects")
        
        // Sort alphabetically (predictable UX)
        allProjects.sort { $0.name.lowercased() < $1.name.lowercased() }
        timer.elapsed("Sorted alphabetically")
        
        // Save to cache for next run
        // Second run will be: cache hit (100ms) + async rescan (non-blocking)
        // This is the 100x speedup from Phase A (ddg-c7w)
        cacheManager.saveCache(allProjects)
        timer.elapsed("Saved \(allProjects.count) projects to cache")
        
        // Fire final callback with complete project list
        onAllProjectsFound?(allProjects)
        
        return allProjects
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
