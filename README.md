# NoGamePosts

Hides Reddit Games / Interactive posts from your feed.

## What it hides
- Reddit Games cards (the native game widgets)
- Interactive/Prediction posts
- Trivia posts
- Reddit Polls (bonus)

## How it works
1. Hooks `UICollectionView willDisplayCell:` — fires before every feed cell renders
2. Scans cell class name against known Reddit game cell naming patterns
3. Also checks `accessibilityIdentifier` for RN-rendered game components
4. Collapses matching cells (hidden + scale transform) so they take no space
5. Runtime class scan at startup pre-caches any game cell classes already loaded

## Install (TrollStore)
1. Build: `make package` (requires Theos)
2. Transfer `.deb` to device
3. Open in TrollStore → Install

## Install (AltStore / sideload)
Requires Dopamine/rootless jailbreak OR inject via your own cert + `DYLD_INSERT_LIBRARIES` 
wrapper — but TrollStore is the cleanest path.

## Debugging
Check Console.app filtered by `NoGamePosts` — it logs every collapsed cell's class name.
Use those to update `gameClassSubstrings` in `Tweak.x` if Reddit ships new game post types.

## Updating class names
Reddit obfuscates some classes per release. If a game post slips through:
1. Console.app → filter `NoGamePosts` 
2. Find cell class name in logs
3. Add substring to `gameClassSubstrings` in `Tweak.x`
4. Rebuild
