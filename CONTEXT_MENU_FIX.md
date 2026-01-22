# Context Menu Fix - Technical Details

## Problem
Context menu (right-click and control+click) was not appearing on grid cards and sidebar items in devdug-gui.

## Root Cause
NSTextFields (title, type, size, path labels) were added as subviews to ClickableCardView. By default, NSTextFields capture mouse events, which prevented the parent ClickableCardView from receiving right-click and control-click events needed to display the context menu.

The event flow was:
1. User right-clicks on card
2. NSTextView intercepts the event
3. ClickableCardView.rightMouseDown() and menu(for:) never get called
4. No context menu appears

## Solution
Set `refusesFirstResponder = true` on all NSTextFields. This tells the responder chain that these views should not participate in event handling, allowing mouse events to pass through to the parent view.

Applied to:
- Grid cards (4 labels: title, type, size, path) in `createProjectCard()`
- Sidebar items (1 label: item name) in `rebuildSidebarList()`

## Testing
After this fix:
1. **Right-click on grid card** - Context menu appears
2. **Control+click on grid card** - Context menu appears  
3. **Right-click on sidebar item** - Context menu appears
4. **Control+click on sidebar item** - Context menu appears

Example expected menu:
```
Copy Path
---
Open in Finder
Reveal in Finder
---
Open in VSCode
Open in Windsurf
Open in Xcode          [only for Swift/Xcode projects]
---
Open on GitHub         [only for git repos]
```

## Code Changes

### Grid Cards (createProjectCard)
```swift
titleLabel.refusesFirstResponder = true
typeLabel.refusesFirstResponder = true
sizeLabel.refusesFirstResponder = true
pathLabel.refusesFirstResponder = true
```

### Sidebar Items (rebuildSidebarList)
```swift
label.refusesFirstResponder = true
```

## Additional Fix
Removed redundant `as? NSView` cast in scrollSidebarToSelection() - documentView property is already NSView.

## Commits
- `cb44805`: Make NSTextFields transparent to mouse events (main fix)
- `60f3dc1`: Remove redundant cast warning
