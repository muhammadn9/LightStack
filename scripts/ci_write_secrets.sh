#!/bin/bash
# Writes a placeholder Secrets.xcconfig for CI (the real one is git-ignored).
# Values are harmless dummies: enough to build and launch, never to reach a backend.
set -euo pipefail
cd "$(dirname "$0")/.."
cat > Lightstack/Config/Secrets.xcconfig <<'XC'
// CI placeholders only. $() stops xcconfig treating // as a comment.
SUPABASE_URL = https:/$()/placeholder.supabase.co
SUPABASE_ANON_KEY = ci-placeholder-anon-key
GOOGLE_CLIENT_ID = 000000000000-placeholder.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.000000000000-placeholder
XC
