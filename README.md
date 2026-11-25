<p align="center">
  <img src="assets/app_icon.png" width="96" height="96" alt="轻课表图标" />
</p>

<h1 align="center">轻课表</h1>

<p align="center">
  一款基于 Flutter 开发的纯本地、无广告 Android 课表应用，支持多源课表导入、智能三方合并、日常课程管理与 Android 原生桌面小组件。
</p>

## 核心功能

- **多维课表视图**：
  - **周视图**：支持左右滑动切换周次、单双周过滤、隐藏周末（5 列/7 列切换）、本周红线时间指示、同格冲突课程角标与长按标记本周停课/请假。
  - **今日课表**：自动计算当前周次与日期，展示正在上课剩余分钟数、下一节倒计时以及「明天预览」折叠列表。
- **Android 原生桌面小组件**：
  - **4×2 今日宽卡**：展示今日日期、周次、总节数及 2×2 淡彩课程卡片网格（含左侧彩色竖条、时间与教室）。
  - **2×2 今日小卡**：紧凑展示当前或下一节展开信息及紧接课程。
  - 支持课表修改即时同步、跨天自动切换、课后智能前推未结束课程、浅色/深色模式自动适配，以及从「设置 → 桌面小组件」发起桌面添加请求。
  - 在 OPPO 或一加手机上，双指捏合桌面进入编辑模式。如果打开了「卡片中心」，将「全部卡片」滑到底，再通过「插件」选择「轻课表」。
- **多源课表导入与分享**：
  - **教务系统网页导入（WebView）**：内置全国高校教务索引搜索、页面自动探针、新版正方后台课表接口直拉（自动选中当前学年学期）、强智同源 `iframe` 提取与未筛选周次重抓，以及支持嵌套表格的通用 HTML 表格解析。
  - **AI 一键转换**：内置提示词模板，复制提示词 + 课表文字/截图发给任意 AI，粘贴返回的 JSON 即可同时导入课程、开学日期与作息时间表。
  - **文件导入**：支持 `.xlsx`（Excel）、`.csv`、`.ics`（日历文件）与 `.json` 备份文件。
  - **分享与备份**：支持导出标准 `.ics` 日历文件通过系统分享发送给同学或导入系统日历，支持 JSON 一键备份导出与恢复。
- **智能三方合并与高效编辑**：
  - 重复导入新课表时自动比对「新增 / 更新 / 保留手动修改 / 仅旧表存在」，保护手动添加的课程和已修改字段。
  - 分组式添加/编辑课程弹窗：实时预览上课时间段、5 列等宽周次网格、单行 10 色选择与吸底快捷确认栏。
- **多课表与纯本地隐私**：支持多张课表档案切换、自定义每天节数（8~16 节）及作息时间、主题色与浅色/深色模式；无广告、无后台数据收集。

## 下载与安装

前往本仓库右侧 **[Releases](../../releases)** 页面下载最新版安卓安装包：

- **`QingKeBiao-arm64-v8a.apk`（推荐，约 19 MB）**：适用于绝大多数近年的 64 位安卓手机。
- **`QingKeBiao-armeabi-v7a.apk`（约 17 MB）**：适用于较老的 32 位安卓设备。
- **`QingKeBiao-universal.apk`（约 53 MB）**：全架构通用包，不确定手机架构时可直接下载此文件。

## 本地开发与构建

```powershell
# 安装依赖
flutter pub get

# 静态代码检查
dart analyze

# 运行全部单元与组件测试
flutter test

# 在安卓真机或模拟器上调试运行
flutter run

# 构建分架构瘦身正式包（推荐）
flutter build apk --release --split-per-abi
```

## 正式版签名配置

- **本地签名**：复制 [android/key.properties.example](android/key.properties.example) 为 `android/key.properties`（已被 `.gitignore` 忽略，切勿提交到仓库），填入你的 `.jks` 签名证书路径与密码即可。
- **GitHub Actions 自动签名发布**：在仓库 **Settings → Secrets and variables → Actions** 中配置以下 4 个 Secrets 后，推送与新版本对应的 `v*` 标签，即可构建已签名正式包并发布到 GitHub Releases：
  - `ANDROID_KEYSTORE_BASE64`（`.jks` 文件的 Base64 编码）
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
