# TTPlayer-iOS · 千千静听风格的本地音乐播放器

纯 SwiftUI 的 iOS 本地播放器，界面照经典千千静听的「主控 / 歌词 / 播放列表」三段式窗口重做，配一套银灰金属皮肤和一套水墨暗色皮肤。全部离线运行，不联网、不需要账号。

- Bundle ID：`com.lin.ttplayer`
- 版本：1.0.0 (1)
- 最低系统：iOS 16.0
- 构建：XcodeGen + GitHub Actions 出未签名 IPA（全能签 / 轻松签自签安装）

## 功能

### 主控窗口
- LCD 式滚动标题、歌手、格式徽标（MP3 / FLAC / M4A / WAV / AAC…）、采样率与码率读数、已播/总时长
- **24 段实时频谱**：`AVAudioEngine` 在 EQ 输出上挂 tap，2048 点 vDSP 实数 FFT，对数分频，快起慢落；暂停后自然回落
- **四种视觉播放**：点视觉框切换，右下角胶囊直接选；经典频谱（24 段辉光柱体 + 镜面倒影 + 峰值钉）、声波示波器（三层发光曲线）、黑胶脉冲（旋转黑胶 + 36 道光芒）、律动星环（粒子 + 同心能量环），选择记在设置里
- **全屏视觉**：标题栏「视觉」按钮进全屏舞台，放大当前视觉模式，配曲目信息、当前歌词、进度与传输控制，可直接切模式与切皮肤
- **兼容播放通道**：`AVAudioFile` 打不开的文件（非标准 MP3 头、后缀与内容不符、异常 VBR/ID3）自动退回 `AVPlayer`，播放/暂停/拖动进度/后台/锁屏照常，频谱换成跟着播放状态走的柔和动画（这一路 EQ 不生效）
- 可拖动进度条、上一首/播放暂停/下一首、播放模式（顺序 / 单曲循环 / 列表循环 / 随机）、音量推子

### 歌词窗口
- 同名 `.lrc`（`.txt` 兜底）与音频内嵌歌词自动读取；兼容 UTF-8 / GB18030
- 自动滚动并高亮当前行，点任意一行跳转
- `−0.5s` / `+0.5s` 手动对轴，按曲目记忆偏移；「导入 LRC」可从「文件」App 选文件

### 播放列表窗口
- 窗口默认吃满整屏剩余高度（列表随屏幕伸展，不再在底部留空档）；小屏（SE 一类）装不下时整屏可滚动
- 从「文件」App 多选导入音频、歌词，或整文件夹导入（复制进 `Documents/Music/`）；「+ 导入」是菜单：
  「导入歌曲 / 歌词」走 `asCopy` 副本，iCloud Drive 和第三方 App 的文件都能读到；「导入整个文件夹」走安全作用域 + `NSFileCoordinator`
- 下载来的文件没有扩展名、或者 AAC 存成了 `.mp3`，导入时按文件头认出真实格式并改正后缀；`.ncm` / `.qmc` / `.kgm` 等加密缓存直接说明「要先解密」
- **内置 Wi-Fi 传歌**：`NWListener` 起一个轻量 HTTP 服务（默认 8088，占用时自动顺延到 8092），
  面板里给二维码和地址，电脑/手机浏览器打开就能拖拽上传，也可以列出与删除手机上的曲目
- 搜索、滑动删除、拖动排序、长按插播（下一首播放）
- 曲库与设置持久化在 `Documents/library.json`

### 十段均衡器
- `AVAudioUnitEQ(numberOfBands: 10)`：31 / 62 / 125 / 250 / 500 Hz，1 / 2 / 4 / 8 / 16 kHz
- 预设：默认、流行、摇滚、古典、重低音、人声、电子；自定义推子、前级增益、总开关
- 链路：`AVAudioPlayerNode → AVAudioUnitEQ → mainMixerNode`

### 后台与锁屏
- `UIBackgroundModes: audio`、`AVAudioSession(.playback)`
- `MPNowPlayingInfoCenter`（标题 / 歌手 / 专辑 / 时长 / 进度 / 封面；无内嵌封面时现画一张）+
  `MPRemoteCommandCenter`（播放、暂停、上一首、下一首、拖动进度）
- 处理来电等打断与耳机拔出

### 两套皮肤
- **经典银灰**：金属渐变窗户、深蓝 LCD、青色频谱
- **水墨暗色**：宣纸黑底、米色 LCD、朱红点缀、宋体歌词

## 目录结构

```
project.yml                     XcodeGen 工程描述
TTPlayer/
  TTPlayerApp.swift             入口
  Info.plist                    后台音频 / 文件共享 / 本地网络说明
  Core/                         Theme（两套皮肤）、Track、Equalizer、格式化
  Audio/                        AVAudioEngine 播放链、24 段频谱分析
  Playback/                     PlayerStore 中枢、LRC 解析、封面生成
  Library/                      文件库、元数据读取、导入
  Services/                     Wi-Fi 传歌 HTTP 服务、网页、本机 IP
  Views/                        三段式窗口、视觉播放、全屏舞台、歌词、播放列表、EQ、Wi-Fi 面板
  Assets.xcassets/              AppIcon（1024）、AccentColor、LaunchBackground
.github/workflows/build-ipa.yml 未签名 IPA 构建（需要手动提交，见下）
Tools/make_icon.py              图标生成
Tools/verify_project.py         本地自检（swiftc -parse + plist/资源检查）
```

## 构建

### GitHub Actions

工作流在 `.github/workflows/build-ipa.yml`：`xcodegen generate` → `xcodebuild`（`CODE_SIGNING_ALLOWED=NO`）→
打包 `Payload/TTPlayer.app` 成 `TTPlayer-unsigned.ipa` → 上传 artifact 并建 Release。

推送 `main` 或在 Actions 页面手动 `Run workflow` 都会出包。macOS runner 偶尔排不上队，
排太久就手动重跑一次。

### 本地

```bash
brew install xcodegen
xcodegen generate
open TTPlayer.xcodeproj      # 选自己的开发者账号签名后可直接装
```

## 用起来

1. **Wi-Fi 传歌**：手机和电脑连同一个 Wi-Fi，点右上角 Wi-Fi 图标 → 扫码或用浏览器打开面板里的地址 →
   把 `mp3/flac/m4a/wav/aac` 拖进去。歌词用同名 `.lrc` 一起传，播放时自动匹配。
2. **文件导入**：播放列表右上角「导入」是个菜单——「导入歌曲 / 歌词」可多选，「导入整个文件夹」连子目录一起收。
3. **从别的 App 打开**：在「文件」里点开一首歌 → 共享 → 「用千千静听打开」，或微信/QQ 里的「其他应用打开」，
   App 会直接把文件收进曲库（`CFBundleDocumentTypes` + `onOpenURL`）。
4. **Files App**：App 的 `Documents/Music` 已开放（`UIFileSharingEnabled`），在「文件」里也能直接放歌。

## 说明与限制

- 未签名 IPA，需要自签工具；安装前先删桌面旧版，避免签名/缓存冲突。
- 兼容通道播放的歌只能调音量，10 段 EQ 不生效（会在提示条里说明一次）。
- 加密缓存（网易云 `.ncm`、QQ 音乐 `.qmc`/`.mflac`、酷狗 `.kgm`、酷我 `.kwm`）不会解密，导入时直接提示。
- FLAC / ALAC 能否播放取决于系统解码能力（iOS 11 起原生支持 FLAC、ALAC）。
- Wi-Fi 传歌需要同一局域网，首次会请求「本地网络」权限；关闭面板即停止服务。
- 歌词偏移、皮肤、音量、EQ、视觉播放模式、面板折叠状态都会记住；播放进度不跨启动保留。
