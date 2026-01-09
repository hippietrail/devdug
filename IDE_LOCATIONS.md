# devdug: Standard IDE Project Locations

Reference guide for where various IDEs store projects and cache/build artifacts.

## macOS

### Xcode
- **Projects**: Usually in `~/Documents`, `~/Desktop`, or custom locations (no centralized default)
- **Build artifacts**: `~/Library/Developer/Xcode/DerivedData/`
- **Workspace files**: `.xcworkspace` directories within project folders
- **Org cache**: `~/Library/Caches/com.apple.dt.Xcode/`
- **Playgrounds**: `~/Documents/Playground Pages/`

### IntelliJ IDEA (and JetBrains IDEs)
- **Projects**: 
  - Default: `~/IdeaProjects/`
  - RustRover: `~/RustroverProjects/`
  - GoLand: `~/GolandProjects/`
  - CLion: `~/CLionProjects/`
  - AppCode: `~/AppCodeProjects/`
  - PyCharm: `~/PycharmProjects/`
  - WebStorm: `~/WebstormProjects/`
- **Project config**: `.idea/` folder within each project
- **Org cache**: `~/Library/Caches/JetBrains/*/`
- **Logs**: `~/Library/Logs/JetBrains/*/`

### Android Studio
- **Projects**: `~/Android Studio Projects/`
- **Project config**: `.idea/` folder + `.gradle/`
- **SDK/Emulator**: `~/Library/Android/sdk/`
- **Gradle cache**: `~/.gradle/`

### Eclipse
- **Workspace default**: `~/eclipse-workspace/`
- **Other common locations**: 
  - `~/eclipse/` (IDE installation)
  - `~/.eclipse/` (org storage)
  - Custom workspace directories (check `.metadata/` for workspace detection)
- **Project markers**: `.project` file (XML) at project root

### Visual Studio Code
- **Project folders**: No centralized location (user-opened)
- **Settings**: `~/.vscode/`
- **Extensions**: `~/.vscode/extensions/`
- **Workspace files**: `.code-workspace` files (can be anywhere)

### Xcode Command Line Tools
- **Location**: `/Applications/Xcode.app/Contents/Developer/`
- **Alternative**: Check `xcode-select -p`

## Linux

### IntelliJ IDEA (and JetBrains)
- **Projects**: 
  - `~/IdeaProjects/`
  - `~/RustroverProjects/`
  - etc. (same pattern as macOS)
- **Project config**: `.idea/` folder
- **Org cache**: `~/.cache/JetBrains/*/` or `~/.config/JetBrains/*/`

### Android Studio
- **Projects**: `~/Android Studio Projects/` (typical)
- **SDK**: `~/Android/Sdk/` (typical)
- **Gradle**: `~/.gradle/`

### Eclipse
- **Workspace**: `~/eclipse-workspace/` (typical)
- **Check**: `.metadata/` directory to identify eclipse projects

### Visual Studio Code
- **Settings**: `~/.config/Code/` (XDG_CONFIG_HOME)
- **Extensions**: `~/.vscode/extensions/`

## Windows

### Visual Studio
- **Projects**: 
  - `%USERPROFILE%\Documents\Visual Studio <version>\Projects\`
  - `%USERPROFILE%\source\repos\` (newer versions)
- **Local app data**: `%APPDATA%\Microsoft\VisualStudio\`

### IntelliJ IDEA (and JetBrains)
- **Projects**: 
  - `%USERPROFILE%\IdeaProjects\`
  - `%USERPROFILE%\RustroverProjects\`
  - etc. (same pattern)
- **Org cache**: `%APPDATA%\JetBrains\*\`

### Android Studio
- **Projects**: `%USERPROFILE%\Android Studio Projects\`
- **SDK**: `%USERPROFILE%\AppData\Local\Android\Sdk\`
- **Gradle**: `%USERPROFILE%\.gradle\`

### Eclipse
- **Workspace**: `%USERPROFILE%\eclipse-workspace\` (typical)

## Project Type Detection Patterns

### Xcode
- File: `*.xcodeproj/` (directory)
- File: `*.xcworkspace/` (directory)
- File: `*.playground/` (directory)

### IntelliJ / JetBrains
- File: `.idea/` (directory)
- File: `.iml` (IntelliJ Module file)
- File: `*.ipr` (older IntelliJ project format)

### Android Studio
- Markers: `.idea/` + `build.gradle(.kts)`
- File: `local.properties`

### Eclipse
- File: `.project` (XML, contains `<projectDescription>`)
- File: `.metadata/` (in workspace root)

### Gradle
- File: `build.gradle` or `build.gradle.kts`
- File: `gradle/` (wrapper directory)

### Maven
- File: `pom.xml`

### npm/JavaScript
- File: `package.json`
- File: `node_modules/` (cache)

### Python
- File: `pyproject.toml`
- File: `setup.py` or `setup.cfg`
- File: `requirements.txt`

### Rust
- File: `Cargo.toml`
- File: `Cargo.lock`

### Go
- File: `go.mod`
- File: `go.sum`

### Swift (non-Xcode)
- File: `Package.swift` (SPM)

## macOS-Specific Considerations

### Firmlinks (Big Sur+)
- `/var/` → `~/Library/var/` (example: system-wide firmlinks)
- **Important**: Don't count firmlinked directories twice
- Use `stat -f` with `%l` flag or check `st_nlink` to detect symlinks/firmlinks

### Hidden Files/Directories
- Prefix: `.` (example: `.idea/`, `.gradle/`)
- May need `--show-hidden` or equivalent in Swift directory traversal

### Library Caches
- `~/Library/Caches/` often contains IDE build/cache artifacts
- Can be large and safe to clean (IDEs will regenerate)

### Build Artifacts
- Swift: `.build/`, `build/`, `.swiftpm/`
- Xcode: `DerivedData/`, `build/`
- Kotlin/Java/Gradle: `build/`, `.gradle/`

## Notes for devdug

1. **Priority order** for scanning:
   - Check explicit IDE project folders first (IdeaProjects, Android Studio Projects, etc.)
   - Then workspace directories (eclipse-workspace)
   - Then home directory root for scattered projects
   - Then check standard IDE cache locations for abandoned builds

2. **Workspace file parsing**:
   - Eclipse: Parse `.metadata/.plugins/org.eclipse.core.resources/.projects/`
   - IntelliJ: Parse `.idea/modules.xml` or `.idea/misc.xml`
   - Xcode: Parse `.xcworkspace/contents.xcworkspacedata` (XML)

3. **Safe to delete**:
   - `DerivedData/` (Xcode)
   - `.gradle/caches/` (Gradle)
   - `node_modules/` (npm)
   - `build/` directories
   - `target/` (Rust/Maven)
   - `.cache/` directories

4. **Never auto-delete**:
   - Source code directories (unless explicitly requested)
   - `.idea/` config (user settings)
   - Workspace metadata files
