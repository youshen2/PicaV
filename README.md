# PicaV

<p align="center">
  <img src="PicaV/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
       alt="PicaV App Icon" width="128" />
</p>

PicaV 是一个使用 SwiftUI 构建的原生 iOS 番剧与视频客户端。项目参考 PicaX
的导航、详情、设置和内容排版，同时使用平台适配层隔离接口差异。当前完成
AcFan 适配，但界面、状态模型、缓存和播放器都不直接依赖 AcFan，后续可以继续
接入其他平台。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 系统 | iOS / iPadOS 15.2 或更高版本 |
| 推荐构建环境 | Xcode 26 |
| 依赖管理 | Swift Package Manager |
| 播放器 | KSPlayer 2.3.4（包含 FFmpegKit 6.1.4） |

iOS 18 及以上会使用 `matchedTransitionSource` 与
`navigationTransition(.zoom)` 完成卡片到详情页的缩放转场；旧系统自动回退为
兼容导航。iOS 18 及以上还会把搜索放入带 `.search` role 的系统 Tab，旧系统保留
顶栏搜索入口。

## 已实现功能

### 首页、发现与搜索

- 首页频道包含“精选 / 动漫 / 视频 / 里番”，默认选择“精选”。
- 频道选择器拥有独立、稳定的状态；切换 Tab 不会连带重建或刷新选择器。
- 精选和里番读取平台栏目，里番使用独立限制级参数；动漫和视频分别读取自己的
  分类列表与内容列表，不会复用精选数据。
- 栏目名称和布局由平台返回，支持“进站必看”“2026 年新番”“第一人称の主观视觉”
  “经典里番佳作”“热血活络小视频”“必看人气创作者”等服务端栏目。
- 首页栏目支持“查看更多”和“换一批”，更多页支持分页与排序。
- 支持发现、分类、排序、分页和内容搜索。
- 搜索页支持平台热门标签与按平台隔离的搜索历史。
- 漫画条目会在映射和展示入口统一过滤，不进入首页、搜索、收藏、历史或推荐列表。

### 详情、收藏与上传者

- 播放器常驻详情页头图区块；进入详情即准备播放，不再跳转到独立播放页。
- 详情展示封面、背景头图、标题、标签、简介、选集、相关推荐和内容信息。
- 相关推荐位于信息区之前；进入新的推荐详情时会暂停当前详情播放器。
- 支持平台“我的收藏”和“浏览记录”，未登录或平台不支持时保留本地收藏与历史。
- 历史记录会保存并显示固定尺寸封面，也能回填旧记录缺失的图片信息。
- 展示上传者头像、昵称和简介，登录平台账号后可关注或取消关注。
- 所有卡片、帖子、历史、推荐和上传者图片都使用明确尺寸与裁剪规则，避免只限定
  宽高比导致列表跳动。

### 播放器

- 使用 KSPlayer，而不是系统原生控制器直接播放。
- 支持拖拽进度、横向滑动快进/快退、长按临时倍速和最高 5× 播放速度。
- 修复拖动进度后的持续 loading，以及全屏返回内嵌模式后的黑屏问题。
- 全屏播放自动切换横屏，退出全屏后恢复原方向。
- CDN / 播放路线选择位于播放器工具栏。
- 播放源按动漫和视频内容类型解析；漫画不会请求视频播放源。
- 播放进度写入历史，下次进入可继续播放。

### 评论与社区

- 支持详情评论列表、点赞数展示、发表评论、回复和子评论查看。
- 支持公共动态与关注动态、帖子详情、发帖和互动。
- 社区帖子图片使用统一固定尺寸裁剪。
- 社区视频可以在帖子内嵌播放器中直接播放。

### 下载、缓存与本地数据

- 使用 `AVAssetDownloadURLSession` 下载平台提供的 HLS 播放资源。
- 支持选择剧集、后台下载、暂停、继续、失败重试、删除和完成记录清理。
- 播放器会优先使用已完成的本地资源，实现离线观看。
- 图片使用内存与磁盘缓存，并在解码前处理平台图片代理、图片域和异或图片数据。
- 详情缓存只保存安全元数据，不保存临时播放鉴权；空标题、无效 ID、错误响应等
  异常数据不会写入图片或详情缓存。
- 平台令牌保存在 Keychain；登录密码只参与当次认证，不写入本地存储。

### 设置

- 使用与 PicaX 一致的分级设置结构和原生列表风格。
- 根页面只展示可操作入口，不使用彩色图标，也不展示“当前平台能力”或不可修改的
  “内容来源”等只读项目。
- 平台、账号、网络、播放、浏览、存储和关于页面相互独立。
- 服务地址、API 前缀、账号会话、图片域、CDN 线路和本地数据均按平台隔离。

## 当前平台

| 平台 | 默认服务地址 | API 前缀 | 状态 |
| --- | --- | --- | --- |
| AcFan | `https://afsdas1234.5237cs3m.work` | `/api` | 已适配 |

AcFan 首页频道的内容来源如下：

| 频道 | 内容来源 |
| --- | --- |
| 精选 | 平台栏目，普通内容 |
| 动漫 | 动漫分类及其内容列表 |
| 视频 | 视频分类及其内容列表 |
| 里番 | 平台栏目，限制级内容 |

默认服务地址和 API 前缀可在“设置 → 网络与服务器”修改。应用不会把 AcFan
写入通用页面逻辑；它只是当前注册表中的第一个平台适配器。

## 架构

```text
SwiftUI Views
      ↓
ViewModels
      ↓
AnimeAPIClient
      ↓
AnimePlatformAdapter + Capability
      ↓
PlatformRequest / AnimeMapper / CommunityMapper
```

- `AnimePlatformAdapter` 声明请求、鉴权、图片规则和平台能力。
- `PlatformAccountCapability`、`PlatformCommentCapability`、
  `PlatformCommunityCapability`、`PlatformLibraryCapability`、
  `PlatformCreatorCapability` 等能力模型决定页面是否开放相应入口。
- `AnimeAPIClient` 统一执行请求、维护游客与账号会话、解析播放地址。
- `AnimeMapper` 和 `CommunityMapper` 把平台字段转换为通用内容模型。
- `LibraryStore` 维护本地收藏、历史和播放进度。
- `AnimeImageCacheService` 与 `AnimeDetailCacheService` 负责经过校验的安全缓存。
- `VideoDownloadService` 管理系统 HLS 后台下载任务和离线资源。

### 添加新平台

1. 添加新的 `AnimePlatformID`。
2. 实现 `AnimePlatformAdapter`，声明该平台实际支持的能力。
3. 在 `AnimePlatformRegistry` 注册适配器。
4. 提供首页、分类、搜索、详情、播放、评论、社区、收藏和上传者等所需请求。
5. 在映射层补充平台响应字段，不在 SwiftUI 页面中添加平台名称判断。

只要适配器提供相同能力，首页、详情、播放器、评论、社区、媒体库和设置页面都可以
复用。

## 本地运行

1. 使用 Xcode 打开项目：

   ```bash
   open PicaV.xcodeproj
   ```

2. 等待 Swift Package Manager 解析 KSPlayer 与 FFmpegKit。
3. 选择 `PicaV` scheme 和模拟器或真机。
4. 真机构建时选择自己的 Development Team，然后运行。

不签名的通用 iOS 构建：

```bash
xcodebuild \
  -project PicaV.xcodeproj \
  -scheme PicaV \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 构建未签名 IPA

仓库提供与 CI 共用的脚本：

```bash
bash build_unsigned_ipa.sh
```

成功后生成：

```text
build/PicaV-unsigned.ipa
```

该 IPA 未签名，不能像 App Store 应用一样直接安装，需要先使用自己的证书或签名
工具完成签名。

## GitHub Actions 与 Telegram Bot

`.github/workflows/build-unsigned.yml` 会在以下场景执行：

- `main` 分支 push；
- 面向 `main` 的 Pull Request；
- `v*` 版本标签；
- 手动触发。

工作流只编译并上传 `PicaV-unsigned.ipa`，不会生成 Watch、macOS、DMG 或其他产物。
版本标签会自动创建 GitHub Release 并附加 IPA 与提交摘要。

普通构建成功后，Bot 会把“上一次成功构建到本次构建”的 Commit 汇总作为 Caption，
连同 IPA 发送到 Telegram。标签发行会发送版本更新、IPA 和 Release 链接，并置顶
消息。外部 Fork 的 Pull Request 不读取仓库 Secrets，因此只构建产物，不发送消息。

在 GitHub 仓库的 `Settings → Secrets and variables → Actions` 配置：

- `TELEGRAM_BOT_TOKEN`：由 `@BotFather` 创建的机器人 Token。
- `TELEGRAM_CHAT_ID`：公开频道可使用 `@频道用户名`，私有频道使用 `-100` 开头的
  ID。

机器人需要目标频道的发消息和置顶消息权限。任一 Secret 缺失或 Telegram 上传失败
时，对应 Bot Job 会明确失败，IPA 构建产物仍保留在 Actions 中。

## 项目目录

```text
.
├── .github/
│   ├── scripts/       CI 与 Telegram Caption 脚本
│   └── workflows/     IPA 构建、Release 与 Bot
├── PicaV/
│   ├── Models/        通用业务模型
│   ├── Services/      平台、网络、映射、缓存、下载与本地存储
│   ├── ViewModels/    页面状态和异步任务
│   └── Views/         SwiftUI 页面与复用组件
└── build_unsigned_ipa.sh
```

## 说明

客户端依赖对应平台的接口结构、鉴权策略、图片域和 CDN 可用性。平台协议变化时，
应优先更新适配器与映射层，不应在页面中加入平台特例。应用仅提供客户端能力；
平台内容、账号服务及其版权与服务条款由对应平台及权利方负责。
