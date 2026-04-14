# LightStack — Claude Code Rules

## After Every Coding Change

1. **Build first:**
   ```
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Lightstack -destination generic/platform=iOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
   ```
2. If **BUILD FAILED** → fix all errors before proceeding. Never commit broken code.
3. **Commit:** `git add -A && git commit -m "<clear description of what changed>"`
4. **Push:** `git push origin HEAD`

This applies after **EVERY task**, not just at the end of a session. No exceptions.

## Branch

All work goes to `feature/form-analysis` (current branch).

## Code Style

- Swift only, no Objective-C
- SwiftUI views, no UIKit view controllers
- Follow existing AppTheme for all colors, fonts, and spacing
- No new third-party dependencies
- No force-unwraps — use guard/if-let
