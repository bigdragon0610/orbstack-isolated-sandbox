#!/usr/bin/env bash
# OrbStack 隔離マシンを作成し、初回プロビジョニングの完了を待ち、
# 現在のターミナルの terminfo を動的にコピーする（Ctrl+L のクリア等のため）。
#
# 使い方:
#   ./create-machine.sh [machine-name]   # 既定の machine-name は "sandbox"
#
# 追加の作成オプション（ネットワーク隔離・マウント等）が必要な場合は
# EXTRA_ARGS 環境変数で渡す。例:
#   EXTRA_ARGS="--isolate-network --mount ~/project:/work" ./create-machine.sh
set -euo pipefail

NAME="${1:-sandbox}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_DATA="$DIR/cloud-init/user-data.yml"

echo "==> Creating isolated machine '$NAME'"
# shellcheck disable=SC2086
orb create --isolated ${EXTRA_ARGS:-} ubuntu "$NAME" -c "$USER_DATA"

echo "==> Waiting for provisioning (cloud-init + first-login user setup)"
# ログインシェルで入ることで初回ログイン時プロビジョニングも走らせる
orb run -m "$NAME" bash -lc 'sudo cloud-init status --wait >/dev/null 2>&1 || true'

# 現在のターミナルの terminfo をマシンへ動的にコピー（静的な同梱はしない）
if command -v infocmp >/dev/null 2>&1 && [ -n "${TERM:-}" ]; then
  if infocmp -x "$TERM" 2>/dev/null | orb run -m "$NAME" tic -x - 2>/dev/null; then
    echo "==> Installed terminfo for TERM=$TERM"
  else
    echo "==> Skipped terminfo copy for TERM=$TERM (not found locally)"
  fi
fi

echo "==> Done. Enter the machine with: orb -m $NAME"
