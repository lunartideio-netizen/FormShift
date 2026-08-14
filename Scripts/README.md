# Build and release scripts

这些脚本是可审查的发布脚手架，不代表发行流程已经跑通。

## `check-repository.sh`

执行 Swift 构建、测试和仓库敏感文件/FFmpeg 二进制静态检查。

## `build-ffmpeg.sh`

只从本地源码归档构建，不联网下载。仓库已经固定 FFmpeg 8.1.2、官方签名密钥指纹和经签名验证后的 SHA-256，然后执行：

```sh
Scripts/build-ffmpeg.sh /absolute/path/to/ffmpeg-source.tar.xz /absolute/output/directory
```

输出包括 `ffmpeg`、`ffprobe` 与记录实际工具链和 configure 参数的 manifest。归档与锁定哈希不一致时脚本会主动停止。

## `package-app.sh`

需要完整 Xcode，在 Apple Silicon 上构建 release `.app`：

```sh
Scripts/package-app.sh /absolute/output/directory
```

默认不签名。`CODESIGN_IDENTITY=-` 只进行 ad-hoc 本地签名；使用 Developer ID 时显式传入真实 identity。脚本不执行公证，也不宣称产物适合公开分发。

## `package-development-app.sh`

当前电脑只有 Command Line Tools 时，可生成明确标注为开发版的本地 `.app`。脚本强制要求已验证的本地 FFmpeg 产物，并只做 ad-hoc 签名：

```sh
Scripts/package-development-app.sh /absolute/output/directory
```

该产物可以本机验收，但没有 Developer ID 签名和 Apple 公证，不是正式发行版。

## `create-dmg.sh`

把已有 `.app` 放入未签名 DMG：

```sh
Scripts/create-dmg.sh /absolute/path/FormShift.app /absolute/path/FormShift.dmg
```

DMG 容器本身不会自动签名或公证。正式发布仍需独立执行并验证 Developer ID 签名、notarytool 提交与 stapler 验证。
