#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TTPlayer-iOS 本地自检：用 Linux 上的 swiftc 只做语法解析，另外检查
Info.plist、资源目录、project.yml 与图标尺寸。在 GitHub Actions 上仍然由
xcodebuild 做真正的编译。"""

import json
import os
import plistlib
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SWIFTC = os.environ.get("SWIFTC", "/workspace/work/swift-toolchain/usr/bin/swiftc")

ok = True
failures = []
notes = []


def fail(message):
    global ok
    ok = False
    failures.append(message)


def note(message):
    notes.append(message)


def collect_swift_files():
    files = []
    for base, _dirs, names in os.walk(os.path.join(ROOT, "TTPlayer")):
        for name in sorted(names):
            if name.endswith(".swift"):
                files.append(os.path.join(base, name))
    return files


def swift_env():
    """这个容器里的 Swift 工具链链接 libncurses.so.6，系统只带 libncursesw.so.6；
    缺这个软链接时 swift-driver 直接起不来，所以在 /tmp 里补一个。"""
    env = dict(os.environ)
    candidates = ["/usr/lib/x86_64-linux-gnu/libncurses.so.6", "/lib/x86_64-linux-gnu/libncurses.so.6"]
    if any(os.path.exists(path) for path in candidates):
        return env
    wide = "/lib/x86_64-linux-gnu/libncursesw.so.6"
    if os.path.exists(wide):
        shim = "/tmp/ttplayer-swiftlibs"
        os.makedirs(shim, exist_ok=True)
        link = os.path.join(shim, "libncurses.so.6")
        if not os.path.exists(link):
            try:
                os.symlink(wide, link)
            except OSError:
                pass
        existing = env.get("LD_LIBRARY_PATH", "")
        env["LD_LIBRARY_PATH"] = shim + ((":" + existing) if existing else "")
    return env


def parse_sources():
    files = collect_swift_files()
    if not files:
        fail("没有找到 Swift 源文件")
        return

    if not os.path.exists(SWIFTC):
        note(f"未找到 swiftc（{SWIFTC}），跳过语法解析")
        return

    env = swift_env()
    for path in files:
        result = subprocess.run(
            [SWIFTC, "-parse", path],
            capture_output=True, text=True, env=env
        )
        if result.returncode != 0:
            fail(f"swiftc -parse 失败: {os.path.relpath(path, ROOT)}\n{result.stderr.strip()}")
    note(f"swiftc -parse 通过 {len(files)} 个文件")

    # 括号/花括号平衡的粗检查，能抓到被截断的文件
    for path in files:
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        for pair in [("{", "}"), ("(", ")"), ("[", "]")]:
            if text.count(pair[0]) != text.count(pair[1]):
                fail(f"{os.path.relpath(path, ROOT)} 括号不平衡: {pair[0]}{pair[1]}")


def check_plist():
    path = os.path.join(ROOT, "TTPlayer", "Info.plist")
    with open(path, "rb") as handle:
        info = plistlib.load(handle)

    expected = {
        "CFBundleIdentifier": "com.lin.ttplayer",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    }
    for key, value in expected.items():
        if info.get(key) != value:
            fail(f"Info.plist {key} = {info.get(key)!r}，期望 {value!r}")

    if "audio" not in info.get("UIBackgroundModes", []):
        fail("Info.plist 缺少 UIBackgroundModes: audio（后台播放会失效）")
    for key in ["UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"]:
        if info.get(key) is not True:
            fail(f"Info.plist 缺少 {key} = true")
    if not info.get("NSLocalNetworkUsageDescription"):
        fail("Info.plist 缺少 NSLocalNetworkUsageDescription（Wi-Fi 传歌必需）")
    if "_http._tcp" not in info.get("NSBonjourServices", []):
        fail("Info.plist 缺少 NSBonjourServices: _http._tcp")

    note("Info.plist 关键字段齐全")


def check_assets():
    icon = os.path.join(ROOT, "TTPlayer", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    if not os.path.exists(icon):
        fail("缺少 AppIcon-1024.png")
        return
    try:
        from PIL import Image
        with Image.open(icon) as image:
            if image.size != (1024, 1024):
                fail(f"AppIcon 尺寸 {image.size}，需要 1024x1024")
            if image.mode not in ("RGB",):
                fail(f"AppIcon 色彩模式 {image.mode}，需要 RGB（不能带透明通道）")
    except ImportError:
        note("未安装 Pillow，跳过图标尺寸检查")
    for name in ["Contents.json", "AccentColor.colorset/Contents.json",
                 "LaunchBackground.colorset/Contents.json",
                 "AppIcon.appiconset/Contents.json"]:
        path = os.path.join(ROOT, "TTPlayer", "Assets.xcassets", name)
        if not os.path.exists(path):
            fail(f"缺少资源文件 {name}")
            continue
        try:
            with open(path, "r", encoding="utf-8") as handle:
                json.load(handle)
        except Exception as error:  # noqa: BLE001
            fail(f"{name} 不是合法 JSON: {error}")

    note("资源目录与图标检查完成")


def check_project():
    path = os.path.join(ROOT, "project.yml")
    if not os.path.exists(path):
        fail("缺少 project.yml")
        return
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    for needle in ["name: TTPlayer", "com.lin.ttplayer", "INFOPLIST_FILE: TTPlayer/Info.plist",
                   "createIntermediateGroups: false"]:
        if needle not in text:
            fail(f"project.yml 缺少 {needle}")
    note("project.yml 检查完成")


def check_workflow():
    path = os.path.join(ROOT, ".github", "workflows", "build-ipa.yml")
    if not os.path.exists(path):
        fail("缺少 .github/workflows/build-ipa.yml")
        return
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    for needle in ["xcodegen generate", "CODE_SIGNING_ALLOWED=NO", "TTPlayer-unsigned.ipa",
                   "actions/upload-artifact"]:
        if needle not in text:
            fail(f"workflow 缺少 {needle}")
    note("workflow 检查完成")


def main():
    parse_sources()
    check_plist()
    check_assets()
    check_project()
    check_workflow()

    print("=" * 60)
    for item in notes:
        print("·", item)
    if failures:
        print("-" * 60)
        for item in failures:
            print("✗", item)
        print("=" * 60)
        print(f"失败 {len(failures)} 项")
        return 1
    print("=" * 60)
    print("全部检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
