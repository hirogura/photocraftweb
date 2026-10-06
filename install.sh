#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# PhotoCraft Webセルフホスト用インストールスクリプト.
#
#   1. ビルド環境がなければ導入 (build-essential, rustup stable, wasm target, trunk)
#   2. `trunk build --release` で apps/photocraft-web -> dist/web をビルド
#   3. 成果物を public/ に配置し, 3365番ポートで静的配信して使用可能にする
#
# Usage:
#   ./install.sh [--port 3365] [--skip-build] [--no-serve]
#
# ビルド環境が無い場合は導入してから `trunk build --release` する.
#
# Env:
#   PORT                 配信ポート (default: 3365)
#   TRUNK_VERSION        trunkバージョン (default: 0.21.14)
#   SKIP_BUILD=1         ビルドを飛ばして配信だけやり直す
#   NO_SERVE=1           配信(起動)をしない
#
set -euo pipefail

PORT="${PORT:-3365}"
TRUNK_VERSION="${TRUNK_VERSION:-0.21.14}"
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
WEB_DIR="$ROOT/apps/photocraft-web"
DIST_DIR="$ROOT/dist/web"
PUBLIC_DIR="$ROOT/public"

log() { echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# cargo/rustup のPATHを通す (インストール直後対策).
export PATH="$HOME/.cargo/bin:/usr/local/bin:$PATH"

install_system_deps() {
  if ! have apt-get; then
    log "apt-get がないためシステム依存の自動導入をスキップ"
    return 0
  fi
  local missing=()
  for c in gcc make pkg-config curl python3; do
    have "$c" || missing+=("$c")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    log "システム依存は充足済み"
    return 0
  fi
  log "システム依存を導入: ${missing[*]}"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential pkg-config curl ca-certificates python3
}

install_rust() {
  if have cargo && have rustc; then
    log "Rust 済み: $(rustc --version)"
  else
    log "rustup 経由で Rust stable を導入"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable --profile default
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
  log "wasm target を確保"
  rustup target add wasm32-unknown-unknown
}

install_trunk() {
  if have trunk; then
    log "trunk 済み: $(trunk --version)"
    return 0
  fi
  local arch
  arch="$(uname -m)"
  local target=""
  case "$arch" in
    x86_64) target="x86_64-unknown-linux-gnu" ;;
    aarch64) target="aarch64-unknown-linux-gnu" ;;
  esac
  if [ -n "$target" ]; then
    log "trunk v${TRUNK_VERSION} バイナリを取得 (${target})"
    local url="https://github.com/trunk-rs/trunk/releases/download/v${TRUNK_VERSION}/trunk-${target}.tar.gz"
    local tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN
    if curl -sL "$url" -o "$tmpdir/trunk.tar.gz" \
      && tar xzf "$tmpdir/trunk.tar.gz" -C "$tmpdir" \
      && [ -x "$tmpdir/trunk" ]; then
      if [ -w /usr/local/bin ]; then
        mv "$tmpdir/trunk" /usr/local/bin/trunk
      else
        mkdir -p "$HOME/.cargo/bin"
        mv "$tmpdir/trunk" "$HOME/.cargo/bin/trunk"
      fi
      trap - RETURN
      rm -rf "$tmpdir"
      log "trunk 導入: $(trunk --version)"
      return 0
    fi
    trap - RETURN
    rm -rf "$tmpdir"
    log "バイナリ取得に失敗したため cargo install にフォールバック"
  fi
  log "cargo install trunk --locked (数分かかります)"
  cargo install trunk --locked
}

build_web() {
  if [ "$SKIP_BUILD" = "1" ]; then
    log "ビルドをスキップ (--skip-build)"
    return 0
  fi
  log "trunk build --release (初回は数分かかります)"
  (cd "$WEB_DIR" && trunk build --release)
  [ -f "$DIST_DIR/index.html" ] || { echo "error: $DIST_DIR/index.html がありません" >&2; exit 1; }
  local wasm
  wasm="$(ls "$DIST_DIR"/*.wasm 2>/dev/null | head -1 || true)"
  [ -n "$wasm" ] || { echo "error: $DIST_DIR/*.wasm がありません" >&2; exit 1; }
  local size
  size="$(wc -c <"$wasm" | tr -d ' ')"
  log "wasm: $(basename "$wasm") ${size} bytes ($((size / 1048576)) MiB)"
  if [ "$size" -gt 25165824 ]; then
    echo "warning: .wasm が24MiB超 (Cloudflare上限25MiBに接近)" >&2
  fi
}

deploy_public() {
  log "成果物を $PUBLIC_DIR に配置 (3365番配信の実体)"
  mkdir -p "$PUBLIC_DIR"
  cp -f "$DIST_DIR"/index.html "$DIST_DIR"/*.js "$DIST_DIR"/*.wasm "$PUBLIC_DIR/"
  [ -f "$PUBLIC_DIR/index.html" ] || { echo "error: 配置に失敗" >&2; exit 1; }
}

serve() {
  if [ "$NO_SERVE" = "1" ]; then
    log "配信をスキップ (--no-serve)"
    return 0
  fi
  # 既存の同ポート配信があれば止める (public/ 配信の二重起動防止).
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
  log "3365番相当で配信開始: 0.0.0.0:${PORT} -> $PUBLIC_DIR"
  nohup python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$PUBLIC_DIR" \
    >/tmp/photocraft-web-serve.log 2>&1 &
  sleep 2
  if curl -sI "http://localhost:${PORT}/" | head -1 | grep -q "200"; then
    log "疎通OK: curl -I http://localhost:${PORT}/ -> 200"
  else
    echo "error: http://localhost:${PORT}/ に応答がありません. /tmp/photocraft-web-serve.log を確認" >&2
    tail -20 /tmp/photocraft-web-serve.log >&2 || true
    exit 1
  fi
  if ! curl -s "http://localhost:${PORT}/" | grep -q "photocraft-web-.*\\.wasm"; then
    echo "error: :${PORT} がPhotoCraftアプリを返していません (旧placeholderの可能性)" >&2
    exit 1
  fi
}

main() {
  log "ROOT=$ROOT PORT=$PORT"
  install_system_deps
  install_rust
  install_trunk
  build_web
  deploy_public
  serve
  log "完了: ブラウザで http://<ホスト>:${PORT} を開いてください"
}

main
