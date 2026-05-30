#!/usr/bin/env python3
"""用 OpenAI DALL-E 生成猫咪图标并保存到项目"""
import os, sys, json, base64, urllib.request

API_KEY = os.environ.get("OPENAI_API_KEY")
if not API_KEY:
    print("❌ 请先设置环境变量: export OPENAI_API_KEY=sk-...")
    sys.exit(1)

PROMPT = "A cute kawaii cartoon cat icon for a macOS app cleaner utility. The cat is orange and cream with bright friendly eyes, holding a small blue microfiber cloth and polishing a clean silver disk or app window, with tiny sparkles to communicate cleanup and removing junk files. Modern macOS rounded-square app icon, centered composition, soft 3D vector style, pastel mint and sky-blue clean background, polished but simple, readable at small sizes. No text, no letters, no watermark, no clutter."

print("🎨 正在生成猫咪图标...")
req = urllib.request.Request(
    "https://api.openai.com/v1/images/generations",
    data=json.dumps({
        "model": "dall-e-3",
        "prompt": PROMPT,
        "n": 1,
        "size": "1024x1024",
        "response_format": "b64_json"
    }).encode(),
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {API_KEY}"
    }
)

try:
    resp = urllib.request.urlopen(req)
    data = json.loads(resp.read())
    if "error" in data:
        print(f"❌ API 错误: {data['error']}")
        sys.exit(1)
    
    b64 = data["data"][0]["b64_json"]
    img = base64.b64decode(b64)
    
    # 保存到项目资源目录
    target = os.path.join(os.path.dirname(__file__), "..", "Sources", "MacAppClean", "Resources", "AppIcon.png")
    target = os.path.abspath(target)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "wb") as f:
        f.write(img)
    print(f"✅ 猫咪图标已保存到: {target}")
    print(f"   大小: {len(img)} bytes, 1024×1024")

except Exception as e:
    print(f"❌ 请求失败: {e}")
    sys.exit(1)
