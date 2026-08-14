# Third-Party Notices

FormShift 自身使用 GNU GPL v3.0。第三方组件仍受各自许可证与署名要求约束。本文件当前是发布合规清单，不是“所有依赖已经打包完成”的声明。

## Apple SDK frameworks

SwiftUI、Foundation、UniformTypeIdentifiers、ImageIO、PDFKit、AVFoundation、VideoToolbox 等系统框架由 Apple 随 macOS/Xcode 提供。它们不是本仓库再分发的源代码。

## FFmpeg（发行版计划内置，二进制不提交到 Git）

- 项目主页：https://ffmpeg.org/
- 许可证说明：https://ffmpeg.org/legal.html
- 固定版本：`8.1.2`（Hoare）
- 源码归档 URL：`https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz`
- 分离签名 URL：`https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz.asc`
- 发布签名密钥指纹：`FCF986EA15E6E293A5644F10B4322F04D67658D8`
- 源码归档 SHA-256：`464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`
- 验证记录：2026-08-14 使用 ffmpeg.org 发布的公钥与分离签名验证通过，再计算并固定上述 SHA-256。
- 构建配置与编译器版本：由 `Scripts/build-ffmpeg.sh` 生成的 manifest 记录。
- 实际许可证：取决于最终 configure 参数和链接库；启用 GPL 组件时按 GPL 发布，启用 `--enable-version3` 组件时必须确认组合后的适用条款。

### 发布前必须完成

1. 审计最终 `ffmpeg -buildconf`、链接库和 codec/filter 列表，不能只看构建脚本预期。
2. 记录所有外部库（包括 x264/x265 等）的版本、许可证、源码与构建脚本；未记录的库不得进入发行包。
3. 在与二进制相同的 Release 页面提供该二进制对应的完整 Corresponding Source、补丁和构建脚本，或采用 GPLv3 第 6 节允许的其他合规方式。
4. 复核 App 设置中的许可证入口、版权、无担保声明、GPL 文本以及对应源码获取方式。
5. 确认构建没有意外启用 `--enable-nonfree`。任何包含该配置的产物都不得以 GPL 发行。
6. 对实际发布的 `.app`/DMG 重新生成本文件，并由维护者复核。

### 当前明确没有做的事

本仓库不提交 FFmpeg 二进制，也没有声明 x264/x265 等外部编码库已包含。源码身份与哈希已经核验；本地固定构建的实际配置与链接结果已写入 manifest，并确认没有 `--enable-nonfree`、没有非系统动态库。正式发行仍必须完成 Corresponding Source 和 Release 页面审计。
