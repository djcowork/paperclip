#!/usr/bin/env bash
# Plan-B follow-up: bring up an independent paperclip instance inside WSL2 on
# port 3101, install plugin-paperclip-github, seed the same three GitHub App
# secrets, and re-run cycle 1 dispatch. Runs after setup-wsl2-paperclip.sh.
#
# Use:
#   wsl -d paperclip-coma580-runner -u runner -- bash \
#     /mnt/d/paperclip/scripts/wsl2-bring-up-paperclip-instance.sh
#
# Idempotent: re-running re-uses the same paperclip instance, same plugin
# install record, same secret keys.

set -euo pipefail

WORK="$HOME/work"
PAPERCLIP="$WORK/paperclip"
DJCOWORK="$WORK/djcowork2.0"
PORT=3101
INSTANCE_NAME=default
COMPANY_PACKAGE_PATH="$PAPERCLIP/doc/company-packages/compliance-first-ai-company"
CREDS_DIR=/mnt/d/paperclip/tmp/github-app-credentials   # reuse Windows-side creds

log()  { printf "\033[36m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[33m!! %s\033[0m\n" "$*"; }
fail() { printf "\033[31mERR %s\033[0m\n" "$*" >&2; exit 1; }

[ -d "$PAPERCLIP" ] || fail "$PAPERCLIP does not exist -- run setup-wsl2-paperclip.sh first"
[ -d "$DJCOWORK" ]  || fail "$DJCOWORK does not exist -- run setup-wsl2-paperclip.sh first"
[ -f "$CREDS_DIR/app-private-key.pem" ] || fail "GitHub App private key not at $CREDS_DIR/app-private-key.pem"

# --------------------------------------------------------------------------
log "[1/7] kill any prior paperclip on port $PORT"
fuser -k -n tcp $PORT 2>/dev/null || true
sleep 1

# --------------------------------------------------------------------------
log "[2/7] build plugin-paperclip-github (esbuild)"
cd "$PAPERCLIP/packages/plugins/plugin-paperclip-github"
pnpm install --prefer-offline >/dev/null 2>&1 || pnpm install
pnpm build

# --------------------------------------------------------------------------
log "[3/7] launch paperclip on port $PORT (background, logs to ~/paperclip-$PORT.log)"
cd "$PAPERCLIP"
PORT=$PORT HOST=127.0.0.1 nohup pnpm paperclipai run --instance "$INSTANCE_NAME" \
  > "$HOME/paperclip-$PORT.log" 2>&1 &
PID=$!
echo "  pid=$PID, log=$HOME/paperclip-$PORT.log"

# Wait for /api/health.
for i in $(seq 1 60); do
  sleep 2
  if curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    log "  paperclip healthy after ${i}x2s"
    break
  fi
done
curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null || fail "paperclip did not become healthy"

# --------------------------------------------------------------------------
log "[4/7] import compliance-first-ai-company"
# Prefer the WSL2 yaml variant (uses /home/dev/work paths; sed-rewrite to runner's $HOME)
WSL_YAML="$COMPANY_PACKAGE_PATH/.paperclip.wsl2.yaml"
ACTIVE_YAML="$COMPANY_PACKAGE_PATH/.paperclip.yaml"
if [ -f "$WSL_YAML" ]; then
  sed "s|/home/dev|$HOME|g" "$WSL_YAML" > "$ACTIVE_YAML"
fi
npx --yes paperclipai company import "$COMPANY_PACKAGE_PATH" || \
  warn "company import returned non-zero (already imported?)"

# --------------------------------------------------------------------------
log "[5/7] discover the imported company id"
COMPANY_ID=$(
  curl -sS "http://127.0.0.1:$PORT/api/companies" |
    python3 -c "import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('companies',[])
for c in items:
    n=(c.get('name') or '').lower()
    if 'compliance-first' in n:
        print(c.get('id')); break"
)
[ -n "$COMPANY_ID" ] || fail "Compliance-First company not found after import"
echo "  company id: $COMPANY_ID"

# --------------------------------------------------------------------------
log "[6/7] install plugin + register 3 secrets"
# Install plugin from local path.
curl -sS -X POST "http://127.0.0.1:$PORT/api/plugins/install" \
  -H "Content-Type: application/json" \
  -d "{\"packageName\":\"$PAPERCLIP/packages/plugins/plugin-paperclip-github\",\"isLocalPath\":true}" \
  -o "$HOME/plugin-install-$PORT.json" || warn "plugin install POST returned error"

PLUGIN_ID=$(python3 -c "
import json
d=json.load(open('$HOME/plugin-install-$PORT.json'))
print(d.get('id') or '')
")

if [ -z "$PLUGIN_ID" ]; then
  # Already-installed path: read plugins list.
  PLUGIN_ID=$(curl -sS "http://127.0.0.1:$PORT/api/plugins" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('plugins',[])
for p in items:
    if p.get('pluginKey')=='paperclipai.plugin-paperclip-github':
        print(p.get('id')); break")
fi
[ -n "$PLUGIN_ID" ] || fail "plugin install/discovery failed"
echo "  plugin id: $PLUGIN_ID"

# Three secrets (plaintext, since plugin secret-refs are still disabled on
# this paperclip version; config.ts maybeResolve falls back to plain values).
python3 <<PY
import json, urllib.request, urllib.error
secrets = [
  ("GitHub App ID",           "GITHUB_APP_ID",          "3711317",      "paperclip-compliance-first-bot App ID"),
  ("GitHub Installation ID",  "GITHUB_INSTALLATION_ID", "132276922",    "djcowork/djcowork2.0 installation"),
  ("GitHub App Private Key",  "GITHUB_APP_PRIVATE_KEY", open(r"$CREDS_DIR/app-private-key.pem").read(),
                              "paperclip-compliance-first-bot PEM (RS256 signing key)"),
]
for name, key, value, desc in secrets:
  body = json.dumps({"name": name, "key": key, "value": value, "description": desc}).encode()
  req = urllib.request.Request(
      f"http://127.0.0.1:$PORT/api/companies/$COMPANY_ID/secrets",
      data=body, method="POST", headers={"Content-Type":"application/json"}
  )
  try:
    with urllib.request.urlopen(req, timeout=10) as r:
      d = json.loads(r.read())
      print(f"  secret {key}: id={d.get('id')}")
  except urllib.error.HTTPError as e:
    body_err = e.read().decode(errors='replace')[:200]
    print(f"  secret {key}: HTTP {e.code} ({body_err})")
PY

# Push plugin config with plaintext credentials. Do not persist
# mergeQueueEnabled for the compliance-managed djcowork/djcowork2.0
# instance; omitting the field lets plugin config default to true.
python3 <<PY
import json, urllib.request
config = {
  "configJson": {
    "appId": "3711317",
    "privateKeyPem": open(r"$CREDS_DIR/app-private-key.pem").read(),
    "installationId": "132276922",
    "repo": "djcowork/djcowork2.0",
    "defaultBranch": "main",
  }
}
req = urllib.request.Request(
    f"http://127.0.0.1:$PORT/api/plugins/$PLUGIN_ID/config",
    data=json.dumps(config).encode(),
    method="POST",
    headers={"Content-Type":"application/json"},
)
with urllib.request.urlopen(req, timeout=15) as r:
  print(f"  plugin config: {r.status}")
PY

# Bounce plugin so it picks up the new config.
curl -sS -X POST "http://127.0.0.1:$PORT/api/plugins/$PLUGIN_ID/disable" >/dev/null 2>&1 || true
sleep 1
curl -sS -X POST "http://127.0.0.1:$PORT/api/plugins/$PLUGIN_ID/enable" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('  plugin status:', d.get('status'))"

# --------------------------------------------------------------------------
log "[7/7] cross-compile smoke (sanity; Plan B already verified)"
cd "$DJCOWORK"
if cargo check --target x86_64-pc-windows-gnullvm -p djcowork --quiet 2>&1 | tail -5; then
  echo "  cross-compile OK"
else
  warn "cross-compile smoke failed; investigate"
fi

# --------------------------------------------------------------------------
echo
echo "==================================================================="
echo "WSL2 paperclip instance ready."
echo "==================================================================="
echo "URL          : http://127.0.0.1:$PORT/"
echo "Company id   : $COMPANY_ID"
echo "Plugin id    : $PLUGIN_ID"
echo "Repos        : $PAPERCLIP and $DJCOWORK"
echo "Log          : $HOME/paperclip-$PORT.log"
echo
echo "Next: re-run cycle 1 dispatch on this instance (do this from Windows):"
echo "  python D:/paperclip/scripts/seed-violations-from-baselines.py \\"
echo "    --company $COMPANY_ID --project <project-id> \\"
echo "    --baseline-dir /mnt/d/code/djcowork2.0/audit --cycle 1 --base http://127.0.0.1:$PORT"
echo "==================================================================="
