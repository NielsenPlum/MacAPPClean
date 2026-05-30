#!/usr/bin/env bash
# 验证扫描逻辑：列出所有被发现的 .app 并检查重复
set -euo pipefail

echo "=== /Applications 中的 App ==="
# 模拟 Swift BFS：递归查找 .app
find /Applications -name "*.app" -maxdepth 3 -type d 2>/dev/null | while read app; do
    resolved=$(readlink "$app" 2>/dev/null || echo "$app")
    echo "$resolved"
done | sort -u > /tmp/apps1.txt
wc -l < /tmp/apps1.txt
echo "个唯一 App（/Applications）"

echo ""
echo "=== ~/Applications 中的 App ==="
find ~/Applications -name "*.app" -maxdepth 3 -type d 2>/dev/null | while read app; do
    resolved=$(readlink "$app" 2>/dev/null || echo "$app")
    echo "$resolved"
done | sort -u > /tmp/apps2.txt
wc -l < /tmp/apps2.txt
echo "个唯一 App（~/Applications）"

echo ""
echo "=== 总计（去重后）==="
sort -u /tmp/apps1.txt /tmp/apps2.txt > /tmp/apps_all.txt
wc -l < /tmp/apps_all.txt
echo "个唯一 App"

echo ""
echo "=== 重复检查 ==="
sort /tmp/apps1.txt /tmp/apps2.txt | uniq -d | head -5
if [ -z "$(sort /tmp/apps1.txt /tmp/apps2.txt | uniq -d)" ]; then
    echo "无重复 ✓"
fi
