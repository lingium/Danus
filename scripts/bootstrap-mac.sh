#!/usr/bin/env bash
# =============================================================================
# Danus bootstrap for macOS
#
# Goal:
#   - Use the Codex CLI that is already installed on this Mac.
#   - Do NOT install a second @openai/codex copy.
#   - Create an isolated Danus CODEX_HOME under runtime/codex-home.
#   - Keep Danus autonomous (approval_policy = "never").
#   - Use the danus-only permission profile: allow workspace writes, restrict
#     external reads, and protect credentials and local Codex configuration.
#   - Reuse the upstream bootstrap steps for the Python venv, Danus editable
#     install, human-summary Node dependencies, and runtime/runtime.env.
#
# Usage:
#   cd /path/to/Danus
#   bash scripts/bootstrap-mac.sh
#
# Optional override:
#   DANUS_SYSTEM_CODEX=/path/to/codex bash scripts/bootstrap-mac.sh
#
# This script is intended for the Danus "codex" branch on macOS.
# It is idempotent: rerunning it reuses a healthy venv and preserves an existing
# runtime/codex-home/config.toml.

# bootstrap-mac.sh
# 1. 使用 Mac 已有 node/npm
# 2. 创建 Python venv
# 3. pip 安装完全相同的核心 Danus dependencies
# 4. 不安装 Codex
#    ↓
#    使用 /opt/homebrew/bin/codex
# 5. 安装 human-summary Node deps
# 6. 写 runtime/runtime.env
# 7. 建立独立 CODEX_HOME
# 8. 使用仓库维护的 bin/codex wrapper
# 9. 配置 danus-only 权限模板
# 10. 处理 macOS 缺少 setsid 的问题
# =============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DANUS_ROOT="$(cd "$HERE/.." && pwd)"
RT="$DANUS_ROOT/runtime"

log()  { printf '[bootstrap-mac] %s\n' "$*"; }
warn() { printf '[bootstrap-mac] WARN: %s\n' "$*" >&2; }
die()  { printf '[bootstrap-mac] FATAL: %s\n' "$*" >&2; exit 1; }

run_nice() {
  if command -v nice >/dev/null 2>&1; then
    nice -n 19 "$@"
  else
    "$@"
  fi
}

# -----------------------------------------------------------------------------
# 0) Platform + existing host tools
# -----------------------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "this bootstrap is for macOS only"

mkdir -p \
  "$RT/logs" \
  "$RT/run" \
  "$RT/tmp" \
  "$RT/codex-home"

PYBASE="$(command -v python3 || true)"
NODE="$(command -v node || true)"
NPM="$(command -v npm || true)"

[ -n "$PYBASE" ] || die "python3 not found on PATH"
[ -n "$NODE" ]   || die "node not found on PATH"
[ -n "$NPM" ]    || die "npm not found on PATH"

# Resolve the base interpreter before a moved/broken venv is renamed or removed.
# PATH may point at that very venv when the operator has activated it.
PYBASE="$("$PYBASE" -c 'import os, sys; print(os.path.realpath(f"{sys.base_prefix}/bin/python{sys.version_info.major}.{sys.version_info.minor}"))')" \
  || die "could not resolve the base Python interpreter"
[ -x "$PYBASE" ] || die "base Python is not executable: $PYBASE"

NODE_MAJOR="$("$NODE" -p 'Number(process.versions.node.split(".")[0])')"
if [ "$NODE_MAJOR" -lt 22 ]; then
  die "Node >= 22 is required for this macOS bootstrap; found $("$NODE" --version)"
fi

# Prefer the user's explicitly supplied Codex, then the Homebrew path used on
# Apple Silicon, then the first Codex on PATH that is not Danus/bin/codex.
SYSTEM_CODEX="${DANUS_SYSTEM_CODEX:-}"

if [ -z "$SYSTEM_CODEX" ] && [ -x /opt/homebrew/bin/codex ]; then
  SYSTEM_CODEX="/opt/homebrew/bin/codex"
fi

if [ -z "$SYSTEM_CODEX" ]; then
  CANDIDATE="$(command -v codex || true)"
  if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "$DANUS_ROOT/bin/codex" ]; then
    SYSTEM_CODEX="$CANDIDATE"
  fi
fi

[ -n "$SYSTEM_CODEX" ] || die \
  "no host Codex CLI found; set DANUS_SYSTEM_CODEX=/absolute/path/to/codex"

[ -x "$SYSTEM_CODEX" ] || die "Codex is not executable: $SYSTEM_CODEX"

case "$SYSTEM_CODEX" in
  "$DANUS_ROOT/bin/codex")
    die "DANUS_SYSTEM_CODEX points to Danus/bin/codex itself; this would recurse"
    ;;
esac

log "repo       : $DANUS_ROOT"
log "python     : $PYBASE ($("$PYBASE" --version 2>&1))"
log "node       : $NODE ($("$NODE" --version))"
log "npm        : $NPM ($("$NPM" --version))"
log "host Codex : $SYSTEM_CODEX ($("$SYSTEM_CODEX" --version 2>&1 | head -1))"

# -----------------------------------------------------------------------------
# 1) Python venv + dependencies
#
# Mirrors upstream scripts/bootstrap.sh:
#   mcp, fastapi, uvicorn, pydantic, openai, anthropic
# plus an editable install of Danus itself.
# -----------------------------------------------------------------------------

VENV="$RT/venv"
export PIP_DISABLE_PIP_VERSION_CHECK=1

DEPS_CHECK='import mcp,fastapi,uvicorn,pydantic,openai,anthropic'

# venv activation scripts and entry-point shebangs are not relocatable.
# Preserve a moved environment for recovery, then build at the current path.
if [ -f "$VENV/bin/activate" ] && ! grep -Fq "$VENV" "$VENV/bin/activate"; then
  VENV_BACKUP="$VENV.before-move-$(date +%Y%m%d%H%M%S)"
  log "moved venv : preserving at $VENV_BACKUP"
  mv "$VENV" "$VENV_BACKUP"
fi

if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "$DEPS_CHECK" 2>/dev/null; then
  log "venv       : present + healthy"
else
  if [ -e "$VENV" ]; then
    log "venv       : missing/broken; rebuilding"
    rm -rf "$VENV"
  fi

  log "creating venv -> $VENV"
  "$PYBASE" -m venv "$VENV"

  log "installing Python dependencies"
  run_nice "$VENV/bin/python" -m pip install --quiet --no-cache-dir --upgrade pip >/dev/null 2>&1 || true
  run_nice "$VENV/bin/python" -m pip install --quiet --no-cache-dir \
    "mcp>=1.0.0" \
    "fastapi>=0.110.0" \
    "uvicorn>=0.30.0" \
    "pydantic>=2.0" \
    "openai>=2.40" \
    "anthropic>=0.92" \
    || die "pip dependency installation failed"

  "$VENV/bin/python" -c "$DEPS_CHECK" \
    || die "Python dependencies are still unavailable after installation"
fi

# Editable install is validated from /, exactly to avoid the repo cwd masking a
# missing package installation.
if (cd / && "$VENV/bin/python" -c 'import danus' 2>/dev/null); then
  log "danus pkg  : editable install already usable"
else
  log "installing Danus package editable into venv"
  run_nice "$VENV/bin/python" -m pip install --quiet --no-cache-dir -e "$DANUS_ROOT" \
    || die "pip install -e failed"

  (cd / && "$VENV/bin/python" -c 'import danus') \
    || die "Danus is still not importable outside the repo"
fi

# -----------------------------------------------------------------------------
# 2) Node dependencies for the human-summary skill
#
# Unlike upstream bootstrap.sh, we use the host npm instead of provisioning a
# private Node 22 tree.
# -----------------------------------------------------------------------------

HS="$DANUS_ROOT/.agents/skills/human-summary"

if [ -d "$HS" ] && [ ! -d "$HS/node_modules/katex" ]; then
  log "installing human-summary Node dependencies"
  (
    cd "$HS"
    run_nice "$NPM" install --no-fund --no-audit >/dev/null 2>&1
  ) || warn "human-summary npm install failed; PDF rendering may not work"
else
  log "human-summary Node deps: already present or skill absent"
fi

# -----------------------------------------------------------------------------
# 3) macOS setsid compatibility
#
# Danus scripts/services.sh uses `setsid`, which is standard on Linux but not on
# a stock macOS install. If no host `setsid` exists, install a tiny local shim in
# Danus/bin. It only implements the form Danus uses: `setsid command args...`.
# -----------------------------------------------------------------------------

if ! command -v setsid >/dev/null 2>&1; then
  log "macOS has no setsid; installing local Danus/bin/setsid shim"

  cat > "$DANUS_ROOT/bin/setsid" <<'PY'
#!/usr/bin/env python3
import errno
import os
import sys

if len(sys.argv) < 2:
    print("usage: setsid command [args ...]", file=sys.stderr)
    raise SystemExit(2)

argv = sys.argv[1:]

try:
    os.setsid()
except OSError as exc:
    if exc.errno != errno.EPERM:
        raise
    # GNU setsid forks when the caller is already a process-group leader.
    pid = os.fork()
    if pid > 0:
        os._exit(0)
    os.setsid()

os.execvp(argv[0], argv)
PY

  chmod 755 "$DANUS_ROOT/bin/setsid"
else
  log "setsid     : $(command -v setsid)"
fi

# -----------------------------------------------------------------------------
# 4) runtime/runtime.env
#
# Upstream bootstrap writes machine-derived Node/Codex/venv paths here.
# On macOS we intentionally do NOT provision DANUS_CODEX_JS. Instead we record
# the one existing host Codex path and let Danus/bin/codex call it directly.
# -----------------------------------------------------------------------------

NODE_BIN_DIR="$(dirname "$NODE")"

cat > "$RT/runtime.env" <<EOF
# Auto-generated by scripts/bootstrap-mac.sh.
# Host tools are discovered by bootstrap; repo paths resolve when sourced.
export DANUS_NODE="$NODE"
export DANUS_NODE_BIN="$NODE_BIN_DIR"
export DANUS_VENV="\$DANUS_ROOT/runtime/venv"
export DANUS_SYSTEM_CODEX="$SYSTEM_CODEX"
EOF

log "wrote       : $RT/runtime.env"

# -----------------------------------------------------------------------------
# 5) Local Danus configuration
#
# Use ChatGPT subscription auth, a separate CODEX_HOME, and force all Danus
# worker/verifier/renderer launches through Danus/bin/codex.
#
# TMPDIR is kept under Danus. This matters because authoring uses Python
# TemporaryDirectory(); keeping it here prevents a workspace-write Codex session
# from acquiring a writable cwd somewhere under /tmp.
# -----------------------------------------------------------------------------

if [ ! -f "$DANUS_ROOT/config/danus.env" ]; then
  cp "$DANUS_ROOT/config/danus.env.example" "$DANUS_ROOT/config/danus.env"
  log "created     : config/danus.env"
fi

if [ ! -f "$DANUS_ROOT/config/codex.env" ]; then
  cp "$DANUS_ROOT/config/codex.env.example" "$DANUS_ROOT/config/codex.env"
  log "created     : config/codex.env"
fi

MAC_MARKER='# --- bootstrap-mac local overrides ---'

if ! grep -Fq "$MAC_MARKER" "$DANUS_ROOT/config/danus.env"; then
  cat >> "$DANUS_ROOT/config/danus.env" <<'EOF'

# --- bootstrap-mac local overrides ---
# Default to ChatGPT only when no backend was selected in the environment or
# earlier config. Keep Danus separate from ~/.codex.
CODEX_BACKEND="${CODEX_BACKEND:-chatgpt}"
CODEX_HOME="$DANUS_ROOT/runtime/codex-home"

# All Danus-spawned Codex sessions must go through the repo wrapper below.
DANUS_CODEX_BIN="$DANUS_ROOT/bin/codex"
# Supply defaults only; preserve configured values and legacy aliases.
DANUS_MAIN_MODEL="${DANUS_MAIN_MODEL:-${DANUS_CODEX_MODEL:-gpt-6-astra}}"
DANUS_MAIN_EFFORT="${DANUS_MAIN_EFFORT:-${DANUS_CODEX_EFFORT:-xhigh}}"

# Keep Python/Codex temporary working directories inside Danus.
TMPDIR="$DANUS_ROOT/runtime/tmp"
# --- end bootstrap-mac local overrides ---
EOF
  log "updated     : config/danus.env"
else
  log "config      : bootstrap-mac overrides already present"
fi

# -----------------------------------------------------------------------------
# 6) Use the repository-maintained wrapper; do not overwrite it at bootstrap.
# -----------------------------------------------------------------------------

[ -x "$DANUS_ROOT/bin/codex" ] || die "repository bin/codex is missing/not executable"

# -----------------------------------------------------------------------------
# 7) Danus-only Codex configuration
#
# Install the repository's danus-only permission template on first setup.
# Repository-specific paths are generated by bin/codex at launch.
# Preserve an existing config.toml instead of clobbering user customizations.
# -----------------------------------------------------------------------------

CODEX_CONFIG="$RT/codex-home/config.toml"

if [ ! -f "$CODEX_CONFIG" ]; then
  cp "$DANUS_ROOT/config/codex-home.config.toml.example" "$CODEX_CONFIG"
  log "created     : $CODEX_CONFIG"
else
  log "Codex config: preserving existing $CODEX_CONFIG"
fi

# -----------------------------------------------------------------------------
# 8) Sanity checks
# -----------------------------------------------------------------------------

log "checking Danus Python environment"
"$VENV/bin/python" -c "$DEPS_CHECK"

log "checking Danus Codex wrapper"
"$DANUS_ROOT/bin/codex" --version

log "done"
printf '\n'
printf 'Next steps:\n'
printf '  1) Login Danus CODEX_HOME once:\n'
printf '       bash scripts/setup-codex.sh login\n'
printf '\n'
printf '  2) Check the login/backend:\n'
printf '       bash scripts/check-codex.sh\n'
printf '\n'
printf '  3) Run the Danus doctor:\n'
printf '       bash scripts/doctor.sh\n'
printf '\n'
printf '  4) Start the verifier when ready:\n'
printf '       bash scripts/services.sh up verify\n'
printf '\n'
printf '  5) Launch the main agent with:\n'
printf '       ./bin/codex\n'
printf '\n'
printf 'Security model:\n'
printf '  - host Codex binary: %s\n' "$SYSTEM_CODEX"
printf '  - Danus CODEX_HOME: %s\n' "$RT/codex-home"
printf '  - permissions: configured in %s\n' "$CODEX_CONFIG"
printf '  - fresh-install default: danus-only (restricted reads, workspace writes)\n'
printf '  - ~/.codex/AGENTS.md is not loaded as Danus global instructions\n'
