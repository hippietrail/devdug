# VCS Detection Testing Guide

## Overview

The `ProjectDiscovery` class in DevdugCore includes git detection that automatically enriches project metadata with:
- `isGitRepo: Bool` - whether project is a git repository
- `gitHost: GitHost` - detected hosting platform (GitHub, GitLab, Codeberg, Gitea, custom, or unknown)
- `gitOriginURL: String?` - the git remote origin URL

All projects are enriched with this metadata during discovery.

## How It Works

### Detection Flow

1. **ProjectDiscovery.discoverProjects(in:)** or **scanHomeDirectory()** iterates projects
2. For each project, **detectGit(at:)** is called during discovery
3. **detectGit()** checks if `.git` directory exists
4. If git repo found, **parseGitOrigin(at:)** reads `.git/config`
5. **detectGitHost(from:)** identifies the hosting platform
6. **extractHostname(from:)** parses custom hostnames from URLs

### Supported URL Formats

- HTTPS: `https://github.com/user/repo.git`
- SSH: `git@github.com:user/repo.git`
- Custom: `https://custom-git.example.com/repo.git`
- SSH Custom: `git@custom-git.example.com:repo.git`

### Detected Hosts

| Host | Detection | Icon |
|------|-----------|------|
| GitHub | `github.com` in URL | 🐙 |
| GitLab | `gitlab.com` in URL | 🦊 |
| Codeberg | `codeberg.org` in URL | 🦆 |
| Gitea | `gitea` in URL | 🍵 |
| Custom | Any other hostname | 📦 |
| Unknown | No .git directory | 🔗 |

## Testing Methods

### Method 1: Quick Script Test

Use the included `test-vcs-detection.swift` script:

```bash
swift ~/test-vcs-detection.swift ~/harper
swift ~/test-vcs-detection.swift ~/devdug
swift ~/test-vcs-detection.swift /tmp  # Non-git project
```

**Output example:**
```
🔍 Testing VCS Detection at: /Users/hippietrail/harper
✅ Git directory found
📄 Git Config Contents:
[remote "origin"]
    url = https://github.com/hippietrail/harper.git
📍 Origin URL: https://github.com/hippietrail/harper.git
🎯 Detected Git Host: GitHub
```

### Method 2: Programmatic Test

```swift
import DevdugCore

let discovery = ProjectDiscovery()
let projects = discovery.discoverProjects(in: ["/Users/hippietrail"])

for project in projects {
    if project.isGitRepo {
        print("\(project.name): \(project.gitHost.displayName) \(project.gitHost.icon)")
        print("  URL: \(project.gitOriginURL ?? "N/A")")
    }
}
```

### Method 3: GUI Testing

Run devdug-gui and:

1. Locate a git project in the grid
2. Right-click (or Control+click) on the project card
3. Verify context menu shows "Open on [Host]" option if git repo detected
4. Click "Open on GitHub" (or other host) to verify browser opens to correct URL

**Test cases:**
- ✅ GitHub projects
- ✅ GitLab projects (if available)
- ✅ Custom git hosts (if available)
- ✅ Non-git projects (should not show git menu option)

### Method 4: Integration Test

Create a simple Swift script to verify end-to-end discovery:

```swift
import DevdugCore
import Foundation

let discovery = ProjectDiscovery()
let allProjects = discovery.discoverProjects(in: discovery.getStandardIDELocations())

let gitProjects = allProjects.filter { $0.isGitRepo }
let githubProjects = gitProjects.filter { $0.gitHost == .github }

print("Total projects: \(allProjects.count)")
print("Git projects: \(gitProjects.count)")
print("GitHub projects: \(githubProjects.count)")

// Show sample
for project in githubProjects.prefix(5) {
    print("  - \(project.name) (\(project.gitOriginURL ?? "no URL"))")
}
```

## Troubleshooting

### VCS Detection Not Working

**Problem:** Projects detected as `isGitRepo: false` despite being git repos

**Debug steps:**
1. Verify `.git` directory exists: `ls -la /path/to/project/.git`
2. Check `.git/config` readability: `cat /path/to/project/.git/config`
3. Verify `[remote "origin"]` section exists in config
4. Check for parse errors in `parseGitOrigin()` by adding debug logging

### Custom Host Not Detected

**Problem:** Custom git host shows as "unknown"

**Debug steps:**
1. Verify origin URL format is supported (see "Supported URL Formats" above)
2. Check that hostname is extractable by `extractHostname()`
3. Verify URL doesn't contain typos or unusual formatting

### Performance Issues

**Note:** Git detection is fast - it only reads `.git/config` (small file)
- File I/O is the bottleneck, not detection logic
- If scanning is slow, consider reducing search directories

## Files Involved

- **Core Logic:** `Sources/DevdugCore/Discovery.swift`
  - `detectGit(at:)` - Main entry point
  - `parseGitOrigin(at:)` - Read config file
  - `detectGitHost(from:)` - Host identification
  - `extractHostname(from:)` - URL parsing

- **Types:** `Sources/DevdugCore/Types.swift`
  - `GitHost` enum with cases and displayName/icon properties
  - `ProjectInfo` struct with git metadata fields

- **GUI Usage:** `devdug-gui/Sources/devdug-gui/main.swift`
  - `ClickableCardView.buildContextMenu()` uses git metadata for menu items
  - `openOnGitHost()` opens git URLs in browser

## Known Limitations

- Only detects origin remote (not upstream or other remotes)
- Does not validate that origin URL is actually reachable
- Does not detect git submodules as separate projects
- Workspace-style repositories (.gitworktree) treated as single git repo
