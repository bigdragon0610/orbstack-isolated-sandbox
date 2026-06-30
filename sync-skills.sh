#!/usr/bin/env bash
# Mac 上の Claude / Kiro の Skills を、隔離マシンへ一方向コピーする。
#
# マウントしない理由: マウント (read-write) すると、サンドボックス内の untrusted
# コードが Mac 上の Skill 定義 (.md) を書き換えられる。書き換えられた Skill は次に
# Mac 側の Claude Code / Kiro が読み込むため、プロンプト注入で隔離を突破されうる。
# そのため tar を stdin 経由でパイプし、一方向にコピーする。
#
# 使い方:
#   ./sync-skills.sh [machine-name]   # 既定の machine-name は "sandbox"
set -euo pipefail

NAME="${1:-sandbox}"

# 同期元（必要なら環境変数で上書き可能）
CLAUDE_SKILLS_SRC="${CLAUDE_SKILLS_SRC:-$HOME/.claude/skills}"
KIRO_SKILLS_SRC="${KIRO_SKILLS_SRC:-$HOME/.kiro/skills}"

# 隔離マシン側の配置先
CLAUDE_SKILLS_DEST='~/.claude/skills'
KIRO_SKILLS_DEST='~/.kiro/skills'

# SOURCE_DIR の中身を DEST_DIR へ tar パイプでコピーする
sync_dir() {
  local src="$1" dest="$2" label="$3"
  if [ ! -d "$src" ]; then
    echo "==> skip $label (not found: $src)"
    return 0
  fi
  echo "==> sync $label: $src -> $NAME:$dest"
  COPYFILE_DISABLE=1 tar czf - --exclude '.DS_Store' -C "$src" . \
    | orb run -m "$NAME" bash -lc "mkdir -p $dest && tar xzf - -C $dest" 2>/dev/null
}

# マシンが起動しているか確認
if ! orb list 2>/dev/null | grep -qE "^${NAME}[[:space:]]+running"; then
  echo "error: machine '$NAME' is not running. Start it with: orb start $NAME" >&2
  exit 1
fi

sync_dir "$CLAUDE_SKILLS_SRC" "$CLAUDE_SKILLS_DEST" "claude skills"
sync_dir "$KIRO_SKILLS_SRC" "$KIRO_SKILLS_DEST" "kiro skills"

echo "==> verify"
orb run -m "$NAME" bash -lc '
  printf "claude skills: "; ls -1 ~/.claude/skills 2>/dev/null | wc -l
  printf "kiro skills:   "; ls -1 ~/.kiro/skills 2>/dev/null | wc -l
' 2>&1

echo "==> done"
