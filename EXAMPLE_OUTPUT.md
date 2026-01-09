# Example Output

Running devdug on a typical hobby OSS developer's machine (5 languages/IDEs):

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

To actually clean these projects, use: devdug --clean
```

With verbose mode (`devdug -v`), each action gets an explanation:

```
🦀 rust-cli-utils (cargo)
  Size: 1.2 GB | Path: ~/projects/rust-cli-utils

  🟢 cargo clean
    Safe command: Removes local build artifacts but keeps source code and .git history.

  🔴 target/
    Safe to delete: Cargo will rebuild on next `cargo build`. Saves most space (~650MB).

  🔴 Cargo.lock
    Safe to delete: Will be regenerated automatically. Only delete if you want dependency updates.

  Estimated recovery: 1.2 GB (100%)
```

And with `devdug --clean`:

```
Cleanup confirmation required for 6 project actions

Project 1/6: 🦀 rust-cli-utils
Ready to delete 1.2 GB. This action includes:
  🟢 cargo clean - Safe command
  🔴 target/ - (650 MB)
  🔴 Cargo.lock - (Optional)

Continue? (yes/no): yes
[1/2] Final confirmation - type 'yes' to proceed: yes
✓ Cleaned rust-cli-utils (1.2 GB recovered)

Project 2/6: 🦀 web-scraper
Ready to delete 856.0 MB. This action includes:
  🟢 cargo clean - Safe command
  🔴 target/ - (450 MB)

Continue? (yes/no): yes
[1/2] Final confirmation - type 'yes' to proceed: yes
✓ Cleaned web-scraper (856.0 MB recovered)

Project 3/6: 🐍 data-processor
Ready to delete 428.0 MB. This action includes:
  🔴 .venv/ - (350 MB)
  🔴 __pycache__/ - (78 MB)

Continue? (yes/no): yes
[1/2] Final confirmation - type 'yes' to proceed: yes
✓ Cleaned data-processor (428.0 MB recovered)

Project 4/6: 📦 react-dashboard
Ready to delete 612.0 MB. This action includes:
  🔴 node_modules/ - (500 MB)
  🔴 .next/ - (112 MB)

Continue? (yes/no): yes
[1/2] Final confirmation - type 'yes' to proceed: yes
✓ Cleaned react-dashboard (612.0 MB recovered)

Project 5/6: 🐹 api-gateway
No cleanup actions defined for this Go project
Continue? (yes/no): no
  Skipped api-gateway

Project 6/6: 💡 desktop-app
Ready to delete 89.0 MB. This action includes:
  🔴 .idea/cache/ - (45 MB)
  🔴 .idea/caches/ - (35 MB)
  🔴 .idea/shelf/ - (9 MB)

Continue? (yes/no): yes
[1/2] Final confirmation - type 'yes' to proceed: yes
✓ Cleaned desktop-app (89.0 MB recovered)

✅ Cleanup complete: 3.2 GB recovered across 5 projects
```
