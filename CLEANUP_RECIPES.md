# Cleanup Recipes for Each Project Type

Empirically determined from your actual projects on disk.

## Rust (cargo)

**Safe command:** `cargo clean`
**Fallback paths:** `target/`
**Measured size:** 817MB (harper)
**Safety:** ✓ Idempotent, always safe. Rebuilds from source.

---

## Node.js / npm

**Safe command:** `npm ci --prefer-offline` (after delete)
**Fallback paths:** `node_modules/`
**Measured sizes:** 
  - 1.3GB (harper)
  - 274MB (harper-electron)
  - 82MB (harper-tauri)
**Safety:** ✓ Safe if lock file exists (package-lock.json, yarn.lock, pnpm-lock.yaml). Regenerates from lock.

---

## Gradle (Java/Kotlin/Android)

**Safe command:** `./gradlew clean`
**Fallback paths:** `build/`
**Measured sizes:**
  - 920KB (harper-kotlin)
  - 434MB (ghidra-repo/ghidra/build - may be ghidra-specific)
**Safety:** ✓ Standard gradle target, always exists.

---

## Swift (SPM)

**Safe command:** `swift build --product <product> --configuration release` (rebuilds)
**Fallback paths:** `.build/`
**Measured size:** 73MB (swift-macos-gui-no-xcode-no-bundle)
**Safety:** ✓ Regenerates from source.

---

## Python

**Safe command:** None (no standard clean)
**Fallback paths:**
  - `__pycache__/`
  - `dist/`
  - `build/`
  - `*.egg-info/` (glob)
  - `.eggs/` (glob)
**Safety:** ✓ Build artifacts only. Source rebuilds from .py files.

---

## CMake / C / C++

**Safe command:** `make clean` (if target exists)
**Fallback paths:**
  - `build/` (common convention)
  - `cmake-build-debug/`
  - `cmake-build-release/`
  - `_build/` (alternative)
**Safety:** ⚠ Depends on project. Use `make clean` if available, else ask user.

---

## Make (generic Makefile projects)

**Safe command:** `make clean` (if target exists)
**Fallback paths:** None standard (varies too much)
**Detection:** `grep -q "^clean:" Makefile && make clean || echo "No clean target"`
**Safety:** ⚠ Check for `clean:` target in Makefile before running.

---

## IntelliJ IDEA / JetBrains IDEs

**Safe command:** None (IDE caches)
**Fallback paths:**
  - `.idea/cache/`
  - `.idea/caches/`
  - `.idea/shelf/`
  - `.idea/modules.xml` (⚠ risky, IDE regenerates)
**Safety:** ⚠ Cache dirs always safe. Don't delete whole `.idea/`.

---

## Eclipse

**Safe command:** None
**Fallback paths:**
  - `.metadata/` (⚠ may require workspace reload)
  - `.recommenders/`
  - `.settings/` (⚠ risky, user-specific)
  - `bin/` (if exists)
**Safety:** ⚠ Workspace may need reload. Only delete `.recommenders/` safely.

---

## Xcode

**Safe command:** None (system-wide, outside project)
**Fallback paths:** `~/Library/Developer/Xcode/DerivedData/<ProjectName>-*/`
**Safety:** ⚠ System-wide. Must match project name in DerivedData. Xcode regenerates on next build.

---

## Visual Studio for Mac

**Fallback paths:**
  - `bin/`
  - `obj/`
  - `.vs/` (hidden folder)
**Safety:** ✓ Build artifacts. Regenerates on build.

---

## Go

**Safe command:** `go clean -modcache` (caches only)
**Fallback paths:** `vendor/` (if exists), `bin/` (if exists)
**Safety:** ⚠ Vendor should only be deleted if `go.mod` exists (not pinned).

---

## Git Repos (generic)

**Safe command:** `git gc --aggressive` (optimize, not delete)
**Fallback paths:** None safe for deletion.
**Safety:** ✗ Don't delete git repos. Only optimize with `git gc`.

---

## Summary Table

| Type | Command | Artifact Path | Size | Safe? |
|------|---------|---------------|------|-------|
| cargo | ✓ cargo clean | target/ | 817MB | ✓ |
| npm | ✓ npm ci | node_modules/ | 1.3GB | ✓ |
| gradle | ✓ ./gradlew clean | build/ | 920KB | ✓ |
| swift-spm | (rebuild) | .build/ | 73MB | ✓ |
| python | — | __pycache/, dist/, build/ | — | ✓ |
| cmake | ? make clean | build/, cmake-build-*/ | — | ⚠ |
| make | ? make clean | (varies) | — | ⚠ |
| intellij-idea | — | .idea/cache*, .idea/shelf/ | — | ⚠ |
| eclipse | — | .recommenders/ only | — | ⚠ |
| xcode | — | ~/Library/Developer/Xcode/DerivedData/*/ | — | ⚠ |
| visual-studio | — | bin/, obj/, .vs/ | — | ✓ |
| go | ✓ go clean | vendor/ | — | ⚠ |
| git-repo | (don't clean) | — | — | ✗ |

