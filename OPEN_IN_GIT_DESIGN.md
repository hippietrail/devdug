# "Open in Git" Action Design

## Current Behavior
- Only shows "Open on [Host]" menu item if `gitOriginURL != nil`
- Only works for remote URLs (not local clones)
- Opens URL in default web browser

## Question: What Should "Open in Git" Do?

Git is a CLI tool, not a website or IDE. So what are the options for "Open in Git" with unknown/custom hosts?

### Option 1: Don't Show It (Current) ✅
- Only show menu item if we can identify the hosting platform
- For unknown hosts: don't show menu item
- **Pros**: Clean, no broken menu items
- **Cons**: Loses git context entirely for unknown hosts

### Option 2: Open Terminal in Project
- Show "Open in Terminal" for any git repo
- Terminal opens in project directory
- User can then run: `git log`, `git status`, `git remote -v`, etc.
- **Pros**: Useful for all repos, any host
- **Cons**: Not really "opening git" - more "open terminal"

### Option 3: Show Git Remote Info
- Right-click → "View Git Info" → shows origin URL
- Could display in a popover or separate window
- User can copy the URL
- **Pros**: Visible, informative
- **Cons**: Extra UI/window, not what "Open in Git" implies

### Option 4: Intelligent URL Opening
- Try to guess the web URL for unknown hosts
- For `git@host.com:user/repo.git`, try `https://host.com/user/repo`
- For `https://internal-git.company.com/project`, use as-is
- **Pros**: Works for many custom hosts
- **Cons**: Fails gracefully but might open wrong URL

### Option 5: Open in Git GUI Tool
- If `gitk` or `GitHub Desktop` or similar is installed
- `gitk` works for any local repo (doesn't need URL)
- **Pros**: Actual git UI, works offline
- **Cons**: Requires external tool, not all users have it

---

## Current Implementation

We chose **Option 1** for pragmatic reasons:

```swift
// Only show if we have a URL to open
if let info = projectInfo, info.isGitRepo, info.gitOriginURL != nil {
    menu.addItem(...)  // "Open on GitHub/GitLab/Custom Host/etc"
}
```

This is **correct** because:
1. Can't open nothing - need a URL
2. Don't show menu items that don't work
3. Repos without origin remote are rare (usually cloned from URL)

---

## Future Improvements

If we want to handle more cases:

### Short-term: Better Host Detection
- Improve VCS detection to identify more custom hosts
- Currently only detects: GitHub, GitLab, Codeberg, Gitea, custom(hostname)
- Could add: Gitee, Bitbucket, Azure DevOps, self-hosted GitLab, etc.

### Medium-term: Terminal Integration
- Add "Open in Terminal" for any project
- Makes sense for git workflow (diff, log, status, etc.)
- Doesn't require identifying the host

### Long-term: Git Info Viewer
- Show git metadata (origin, branches, remotes)
- Could be sidebar panel or popover
- Would be useful for all repos

---

## What We're NOT Doing

❌ "Opening git as an app" - git is CLI-only, not an application  
❌ Trying to guess web URLs - too fragile, better to show nothing  
❌ Terminal shortcuts - separate from VCS linking feature  
❌ Forcing url opening when URL is nil - broken UX

---

## Related Feature: Open in IDE/Editor

For comparison, we DO show:
- "Open in VSCode" - works for all projects (editor, not VCS-aware)
- "Open in Xcode" - works for Xcode projects (IDE with git integration)
- "Open in Windsurf" - works for all projects (editor, not VCS-aware)

These don't depend on VCS detection. They work by opening the project directory/file in the app.

The VCS menu items are different - they require knowing the URL to be useful.

---

## Decision

**Keep current behavior:**
- Show "Open on [Host]" only when we can resolve the origin URL
- This prevents broken menu items
- Users with unknown hosts can still use other options (Finder, editors, terminal)

**Future option:**
- Add "Open in Terminal" as separate menu item (would be useful for all repos)
- Could show git status/log from terminal
