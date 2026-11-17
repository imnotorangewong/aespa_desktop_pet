#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SOURCE="${1:-../NOT_FOR_PUBLIC_UPLOAD/skins}"
mkdir -p assets-local
for file in spritesheet-clean.png skin-blue-cat.png skin-charcoal-cat.png skin-heart-buddy.png; do
  [[ -f "$SOURCE/$file" ]] || { echo "缺少素材：$SOURCE/$file"; exit 1; }
done
for file in spritesheet-clean.png skin-blue-cat.png skin-charcoal-cat.png skin-heart-buddy.png; do cp "$SOURCE/$file" "assets-local/$file"; done
echo '已复制到被 Git 忽略的 assets-local/；不代表获得公开传播许可。'
