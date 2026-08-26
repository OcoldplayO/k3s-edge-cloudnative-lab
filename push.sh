#!/bin/bash
set -eu
MSG="${1:-update: 自动同步最新云原生编排清单与排障手册}"
git add .
if git diff-index --quiet HEAD --; then
    echo "⚠️ [INFO] 没有检测到文件变动，无需提交。"
    exit 0
fi
git commit -m "${MSG}"
git push origin main
echo "✅ [SUCCESS] 项目全量资产已推送到 GitHub！"
