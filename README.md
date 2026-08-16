# FormShift

FormShift 是一款面向 macOS 的本地格式转换工具。项目目标是把图片、视频、音频、PDF 与 GIF 的常用转换放进一个清楚、可批处理、不会覆盖源文件的原生界面。

> 当前状态：早期开发版本。仓库目前不是可供普通用户安装的稳定发行版，也没有已签名或已公证的 DMG。

当前能做、不能做以及预计开发阶段，见 [《FormShift 当前能力与开发路线》](CAPABILITIES.md)。

## 当前已经实现

- Swift 6 / SwiftUI 的 macOS 15 三栏界面，包含文件/文件夹导入、任务列表、检查器、深浅色和键盘入口。
- `FormShiftCore` 中的格式、媒体描述、转换选项、任务、预设、引擎协议和引擎注册表。
- actor 型转换队列，以及保存最近 30 天任务摘要、源文件安全书签、转换参数和预设的本地 JSON 持久化实现。它是完整 Xcode 环境迁移到 SwiftData 之前的可编译替代，不是最终存储方案。
- ImageIO 转换实现、单张图片生成 PDF/PDF 首页导出图片的实现，以及 FFmpeg/ffprobe 探测、参数规划、进度和取消实现。
- 侧边栏独立「PDF 工作台」，集成四大原生处理模块：多图/单图按序合成多页 PDF（支持自适应、A4、Letter 与边距版式）、多份 PDF/混合文件合并、PDF 拆分（每页一份/固定页数均分/自定义页码区间）、PDF 视觉缩略图页面重排与顺逆时针 90° 旋转剔除，以及 PDF 批量导出图片（整份/单页/自定义区间，1×/2×/3× 渲染精度与智能裁白边）。
- 侧边栏独立「帧工作台」，集成三大媒体动图与帧处理模块：GIF 拆帧批量导出序列图片、连续图片序列按指定帧率/循环次数合成高质量 GIF 动图，以及视频按固定时间间隔/精准时间戳/固定总帧数批量截帧抽取静帧。
- 检查器侧边栏完整开放专业音视频控制：视频码率档位、音频码率档位、精确起止时间裁切、移除音频（静音）以及 EBU R128 音频响度标准化。
- 预设（Presets）支持完整导入与导出：支持将全部或单个预设导出为 `.formshiftpreset` / JSON 文件，并支持一键导入与去重合并。
- 队列常规转换全面支持 PDF 多页批量导出（支持所有页面、仅第一页或自定义页码范围），批量生成清晰命名序列文件。
- 界面已接入真实引擎注册表、转换队列和本地历史桥接；开始、暂停队列、取消、失败重试、跨重启历史恢复、结果定位及固定输出目录均执行真实操作。
- 同一源文件可一次选择多个目标格式；每种格式独立记忆质量、尺寸和专业参数，队列会为每个兼容格式创建独立任务、进度、结果与历史记录。
- 图片支持完整适应、填充裁切、拉伸、智能裁白边、手动裁剪、旋转和 sRGB/Display P3 输出；PDF 首页导出支持 1×/2×/3× 渲染精度。
- 预设支持创建、应用、同名更新、删除和跨重启保存。
- 安全输出路径：默认与源文件同目录、同名自动递增、临时文件名与任务绑定。
- 面向完整 Xcode 的核心 XCTest，以及构建、测试、FFmpeg 构建和本地打包脚本框架。

Debug 与 Release 均已通过 `swift build`。无需 XCTest 的 `FormShiftSmoke` 已真实验证智能裁白边、300×300 填充裁切、Display P3、PDF 1×/3× 渲染差异、单个 PNG 同时生成 JPEG 与 PDF、历史参数恢复与中断任务迁移。开发机另已真实跑通并回读验证 PNG→JPEG、图片→PDF 与 PDF 首页→PNG。FFmpeg 8.1.2 已从官方签名验证过的源码实际构建为 arm64 静态工具，构建时禁用网络并只链接 Apple 系统框架；通过真实队列逐项验证了 MP4 输入导出 MP4、MOV、MKV、GIF、M4A、AAC、WAV、AIFF、FLAC、ALAC、OGG 与 Opus，完成后没有残留临时文件。开发版 `.app` 已验证能优先识别包内 FFmpeg，不依赖 Homebrew 或 PATH。
无需 XCTest 的 `FormShiftSmoke` 进一步真实验证了 PDF 语法范围解析、3 图合成多页 PDF、5 页多文档合并、3 种策略拆分、旋转 90°/180° 与重排剔除、批量图片导出尺寸校验与队列多页连续导出回读。
无需 XCTest 的 `FormShiftSmoke` 同时验证了图片序列合成 GIF 动图与帧数回读、GIF 拆帧导出、预设文件 JSON 序列化与跨会话导入导出。

本机只有 Command Line Tools 且缺少 XCTest 模块，`swift test` 尚未执行成功；测试是否通过需要完整 Xcode 或 CI 给出证据。当前生成的 DMG 仅为 ad-hoc 签名开发构建，没有 Developer ID 签名或 Apple 公证，不能冒充正式发行版。

仓库中的实际能力以代码和自动化测试为准。界面出现某个格式名称，不代表该格式的完整转换链路已经通过验收。

## 计划中，尚未承诺可用

- 正式 Release 的 Developer ID 签名、公证、安装与干净 Mac 验收；当前只有明确标注的本地开发构建。
- MP3 输出、VP9、AV1 与 WebM 输出。当前无外部编码库的固定构建不会声明这些输出；H.264、HEVC 与 ProRes 使用实际可用的 VideoToolbox/原生编码器。

WebP、AVIF 与具体图片编码能力由 ImageIO 在运行时检测；没有编码器的格式不会进入输出能力表。Office、OCR、电子书、压缩包和 AI 不属于首版范围。

## 系统要求

- Apple Silicon Mac。
- macOS 15 或更高版本。
- `swift build` 可使用当前 Command Line Tools；运行 XCTest、完整 Xcode 工程验收和正式发布需要完整 Xcode。

## 开发

```sh
swift build
swift test
```

`swift test` 需要提供 XCTest 的完整 Xcode。当前开发机的 Command Line Tools 环境会报告 `no such module 'XCTest'`，这不是测试通过记录。

本地生成 `.app` 与 DMG 的方法见 `Scripts/README.md`。这些脚本不会替你完成 Developer ID 签名或 Apple 公证。

FFmpeg 二进制不提交到仓库。`Scripts/build-ffmpeg.sh` 只接受与固定 SHA-256 一致的 FFmpeg 8.1.2 官方源码归档。发布 FFmpeg 时必须同时完成 `THIRD_PARTY_NOTICES.md` 中的合规清单。

## 隐私与安全

设计目标是完全本地转换：无账号、无上传、无广告、无遥测，也不允许转换引擎静默下载组件。当前实现和正式发行版之间仍有差距；隐私承诺与边界见 [PRIVACY.md](PRIVACY.md)，漏洞报告方式见 [SECURITY.md](SECURITY.md)。

## 许可

FormShift 以 GNU General Public License v3.0 发布，见 [LICENSE](LICENSE)。第三方组件保留各自许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
