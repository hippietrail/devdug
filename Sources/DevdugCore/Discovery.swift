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

    public func discoverProjects(in locations: [String]) -> [ProjectInfo] {
        var projects: [ProjectInfo] = []
        
        for location in locations {
            guard fileManager.fileExists(atPath: location) else { continue }
            
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: location)
                for item in contents {
                    let fullPath = (location as NSString).appendingPathComponent(item)
                    
                    if let projectType = detectProjectType(at: fullPath) {
                        do {
                            let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
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

    public func scanHomeDirectory() -> [ProjectInfo] {
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
                        let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
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
        
        // Check for various project markers
        let indicators: [(String, String)] = [
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
        
        for (marker, type) in indicators {
            let markerPath = (path as NSString).appendingPathComponent(marker)
            if fileManager.fileExists(atPath: markerPath) {
                return type
            }
        }
        
        return nil
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
