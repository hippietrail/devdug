# devdug

![devdug logo](logo4.svg)

Will be a fast, safe tool for discovering and cleaning up scattered dev projects on macOS/Linux.

**Safety first**: devdug will enforce manual confirmations to prevent accidental data loss. You must review the cleanup plan before execution, and confirm each action individually.

## Quick Start

```bash
./devdug          # Discover projects & show cleanup strategy
./devdug --clean  # Will review and confirm cleanup actions
./devdug -v       # Verbose mode: explain each cleanup action
```

## Example

```
Discovery scan complete

🦀 rust-cli-utils (cargo)
  Size: 1.2 GB | Path: ~/projects/rust-cli-utils
  target/
  Cargo.lock

🦀 web-scraper (cargo)
  Size: 856.0 MB | Path: ~/projects/web-scraper
  target/
  Cargo.lock

🐍 data-processor (python-poetry)
  Size: 428.0 MB | Path: ~/projects/data-processor
  .venv/
  __pycache__/

📦 react-dashboard (npm)
  Size: 612.0 MB | Path: ~/projects/react-dashboard
  node_modules/
  .next/

🐹 api-gateway (go)
  Size: 245.0 MB | Path: ~/projects/api-gateway
  No automatic cleanup defined

💡 desktop-app (intellij-idea)
  Size: 89.0 MB | Path: ~/IdeaProjects/desktop-app
  .idea/cache/
  .idea/caches/
  .idea/shelf/

Estimated space to reclaim: 3.4 GB

💰 Biggest disk space savings:
  🦀 rust-cli-utils (cargo): 1.2 GB
  🦀 web-scraper (cargo): 856.0 MB
  📦 react-dashboard (npm): 612.0 MB

Yellow actions (⚠️  tentative) require manual verification.
Red paths will be permanently deleted.
Green commands are safe to run.

🦀 cargo  🐹 go  💡 intellij-idea  📦 npm  🐍 python-poetry

Total disk space: 3.4 GB

To actually clean these projects, you would use: devdug --clean
```

## Features

- **Safe by design**: Enforced manual confirmations, dual-confirm for destructive actions
- **Comprehensive project support**: Cargo, npm, Python, Gradle, Maven, Make, CMake, Go, Swift, Xcode, IntelliJ, Android Studio, Eclipse, and more
- **Visual feedback**: Color-coded cleanup actions (🟢 safe, 🟡 tentative, 🔴 destructive)

## Supported Project Types

- **Rust**: Cargo (`target/`, `Cargo.lock`)
- **Python**: Poetry (`.venv/`, `__pycache__/`), pip, setuptools
- **Node.js**: npm/yarn (`node_modules/`, `.next/`, build outputs)
- **Java**: Gradle, Maven, IntelliJ IDEA
- **Go**: No automatic cleanup (safe to keep)
- **C/C++**: Make, CMake build artifacts
- **JVM IDEs**: IntelliJ IDEA, Android Studio, Rustrover, CLion, Goland, PyCharm, WebStorm, AppCode
- **macOS**: Xcode, Swift Package Manager
- **Other**: Eclipse, Visual Studio for Mac, general git repositories
- **Suggest more!**

## Contributing

Contributions welcome! This project was just born and is still being sketched out:

- **New project type cleanup recipes**: PRs adding support for new language ecosystems (Haskell, Elixir, Julia, etc.)
- **Platform support**: Windows cleanup strategies, additional macOS IDE detection
- **Bug reports**: IDE detection edge cases, false positives in discovery

Open an issue or PR to discuss ideas before major changes.

## Safety Philosophy

devdug was born from losing an Android Studio workspace to careless cleanup. The tool enforces:

1. **Mandatory preview**: Default mode shows full cleanup plan without executing anything
2. **Manual confirmations**: No `-y`/`--force` flags—every project requires explicit confirmation
3. **Dual-confirm for destructive actions**: Deletion requires typing "yes" twice
4. **Verbose explanations**: Understand *why* each cleanup is safe before proceeding
