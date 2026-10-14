#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# GridCraft Webセルフホスト用インストールスクリプト (Node.js+Vite+React用).
#
#   1. Node.jsがなければ導入 (apt または nodesource)
#   2. https://github.com/Rohan-Shridhar/gridcraft.git を gridcraft/ に取得 (既存なら pull)
#   3. `npm ci && npm run build` で dist/ をビルド
#   4. 成果物を public-gridcraft/ に配置し, 3366番ポートで静的配信して使用可能にする
#
# Usage:
#   ./gridcraftweb-install.sh [--port 3366] [--skip-build] [--no-serve]
#
# Env:
#   PORT                 配信ポート (default: 3366)
#   SKIP_BUILD=1         ビルドを飛ばして配信だけやり直す
#   NO_SERVE=1           配信(起動)をしない
#
set -euo pipefail

PORT="${PORT:-3366}"
SKIP_BUILD="${SKIP_BUILD:-0}"
NO_SERVE="${NO_SERVE:-0}"

for arg in "$@"; do
  case "$arg" in
    --port=*) PORT="${arg#--port=}" ;;
    --port) shift_arg=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --no-serve) NO_SERVE=1 ;;
    --help|-h)
      sed -n '2,19p' "$0"
      exit 0
      ;;
    *)
      if [ "${shift_arg:-0}" = "1" ]; then
        PORT="$arg"
        shift_arg=0
      else
        echo "error: unknown arg: $arg (see --help)" >&2
        exit 1
      fi
      ;;
  esac
done
export PORT

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT/gridcraft"
DIST_DIR="$SRC_DIR/dist"
PUBLIC_DIR="$ROOT/public-gridcraft"
REPO_URL="https://github.com/Rohan-Shridhar/gridcraft.git"

log() { echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

install_system_deps() {
  if ! have apt-get; then
    log "apt-get がないためシステム依存の自動導入をスキップ"
    return 0
  fi
  local missing=()
  for c in curl ca-certificates python3 git; do
    have "$c" || missing+=("$c")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    log "システム依存は充足済み"
    return 0
  fi
  log "システム依存を導入: ${missing[*]}"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl ca-certificates python3 git
}

install_node() {
  if have node && have npm; then
    log "Node.js 済み: $(node --version) / npm $(npm --version)"
    return 0
  fi
  if have apt-get; then
    log "Node.js を導入 (apt)"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs npm \
      || {
        log "apt での導入に失敗したため nodesource から導入"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
      }
  else
    echo "error: node/npm がなく自動導入できません. 手動で Node.js 20系を導入してください" >&2
    exit 1
  fi
  log "Node.js 導入: $(node --version) / npm $(npm --version)"
}

fetch_src() {
  if [ -d "$SRC_DIR/.git" ]; then
    log "gridcraft/ 既存のため pull で更新"
    (cd "$SRC_DIR" && git pull --ff-only)
  elif [ -d "$SRC_DIR" ]; then
    echo "error: $SRC_DIR が存在しますが git リポジトリではありません" >&2
    exit 1
  else
    log "gridcraft を clone: $REPO_URL"
    git clone "$REPO_URL" "$SRC_DIR"
  fi
}

build_web() {
  if [ "$SKIP_BUILD" = "1" ]; then
    log "ビルドをスキップ (--skip-build)"
    return 0
  fi
  log "npm ci && npm run build"
  (cd "$SRC_DIR" && npm ci && npm run build)
  [ -f "$DIST_DIR/index.html" ] || { echo "error: $DIST_DIR/index.html がありません" >&2; exit 1; }
}

deploy_public() {
  log "成果物を $PUBLIC_DIR に配置 (3366番配信の実体)"
  mkdir -p "$PUBLIC_DIR"
  cp -rf "$DIST_DIR"/. "$PUBLIC_DIR"/
  [ -f "$PUBLIC_DIR/index.html" ] || { echo "error: 配置に失敗" >&2; exit 1; }
}

serve() {
  if [ "$NO_SERVE" = "1" ]; then
    log "配信をスキップ (--no-serve)"
    return 0
  fi
  if have fuser; then
    fuser -k "${PORT}/tcp" 2>/dev/null || true
    sleep 1
  else
    local pids
    pids="$(ps -eo pid,args | grep "[h]ttp.server ${PORT} " | awk '{print $1}' || true)"
    if [ -n "$pids" ]; then
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
      sleep 1
    fi
  fi
  log "3366番相当で配信開始: 0.0.0.0:${PORT} -> $PUBLIC_DIR"
  nohup python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$PUBLIC_DIR" \
    >/tmp/gridcraft-web-serve.log 2>&1 &
  sleep 2
  if curl -sI "http://localhost:${PORT}/" | head -1 | grep -q "200"; then
    log "疎通OK: curl -I http://localhost:${PORT}/ -> 200"
  else
    echo "error: http://localhost:${PORT}/ に応答がありません. /tmp/gridcraft-web-serve.log を確認" >&2
    tail -20 /tmp/gridcraft-web-serve.log >&2 || true
    exit 1
  fi
}

main() {
  log "ROOT=$ROOT PORT=$PORT"
  install_system_deps
  install_node
  fetch_src
  build_web
  deploy_public
  serve
  log "完了: ブラウザで http://<ホスト>:${PORT} を開いてください"
}

main
