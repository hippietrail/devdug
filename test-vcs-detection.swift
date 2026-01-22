#!/usr/bin/env swift
import Foundation

// Add devdug to the module search path and import
// Usage: swift test-vcs-detection.swift <project-path>

// Quick inline test of VCS detection without full integration
// This tests the git detection logic by examining .git/config directly

func testVCSDetection(at projectPath: String) {
    print("🔍 Testing VCS Detection at: \(projectPath)")
    
    let gitDir = (projectPath as NSString).appendingPathComponent(".git")
    let configFile = (projectPath as NSString).appendingPathComponent(".git/config")
    
    let fm = FileManager.default
    
    // Check if git repo exists
    if !fm.fileExists(atPath: gitDir) {
        print("❌ Not a git repository (no .git directory)")
        return
    }
    
    print("✅ Git directory found")
    
    // Try to read config
    guard let content = try? String(contentsOfFile: configFile, encoding: .utf8) else {
        print("❌ Cannot read .git/config")
        return
    }
    
    print("\n📄 Git Config Contents:")
    print("---")
    print(content)
    print("---\n")
    
    // Parse origin URL
    var inRemoteSection = false
    var originURL: String?
    
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed == "[remote \"origin\"]" {
            inRemoteSection = true
            continue
        }
        
        if trimmed.starts(with: "[") && inRemoteSection {
            break
        }
        
        if inRemoteSection && trimmed.starts(with: "url =") {
            let urlPart = trimmed.dropFirst("url =".count).trimmingCharacters(in: .whitespaces)
            originURL = String(urlPart)
            break
        }
    }
    
    guard let url = originURL else {
        print("⚠️  No origin URL found in [remote \"origin\"]")
        return
    }
    
    print("📍 Origin URL: \(url)")
    
    // Detect host
    let lowerURL = url.lowercased()
    var detectedHost: String?
    
    if lowerURL.contains("github.com") {
        detectedHost = "GitHub"
    } else if lowerURL.contains("gitlab.com") {
        detectedHost = "GitLab"
    } else if lowerURL.contains("codeberg.org") {
        detectedHost = "Codeberg"
    } else if lowerURL.contains("gitea") {
        detectedHost = "Gitea"
    } else {
        // Extract hostname
        if let atIndex = url.firstIndex(of: "@") {
            // git@hostname:path format
            let afterAt = url[url.index(after: atIndex)...]
            if let colonIndex = afterAt.firstIndex(of: ":") {
                detectedHost = String(afterAt[..<colonIndex])
            }
        } else if url.contains("://") {
            // https://hostname/path format
            if let schemeEndIndex = url.range(of: "://")?.upperBound {
                let afterScheme = url[schemeEndIndex...]
                if let slashIndex = afterScheme.firstIndex(of: "/") {
                    detectedHost = String(afterScheme[..<slashIndex])
                }
            }
        }
    }
    
    if let host = detectedHost {
        print("🎯 Detected Git Host: \(host)")
    } else {
        print("❓ Unknown git host")
    }
}

// Main
let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: \(args[0]) <project-path>")
    print("Example: \(args[0]) /Users/hippietrail/harper")
    exit(1)
}

let projectPath = args[1]
testVCSDetection(at: projectPath)
