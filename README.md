# y4m-inspect

MoonBit 增量 YUV4MPEG2 校验器原型，用于发现头部错误和截断帧，输出帧计数与亮度范围。包含 MoonBit 流式解析库和可从文件或标准输入读取字节流的命令行工具。

## 回归样本

| 文件 | 场景 | 判定标准 |
|---|---|---|
| two-frames.y4m | 2×2、8 位单色、25 fps、双帧；首帧像素含换行字节 | 完整两帧，亮度范围 [0,255]、[7,7] |
| truncated.y4m | 上述素材缺最后一个字节 | 第二帧不完整，缺 1 字节 |

原始字节由本项目合成，无需外部视频。机器可读期望见 expected.json。
项目边界与拟交付项见 [项目申报说明](proposal.pdf)。流式接口在输入按单字节或任意分块交付时，保持输出和错误一致。


## 运行与验证

安装官方 MoonBit 工具链，运行 `moon test --target wasm-gc`。使用本地官方版 2026-11-17 验证：5 个测试通过。核心库按块接收 Bytes，并在帧完整时同步回调输出帧号（从零开始）、亮度最小值与最大值。finish 返回视频元数据与帧数，截断时返回缺少字节数。

支持 8 位 mono 和偶数宽高的 420jpeg。只提取 W/H/F/C，接受但不解读 A/I/X；未指定帧率时返回 0/0。拒绝超过 8192 字节的头部、超过 67108864 个亮度像素的单帧，以及未支持的色彩格式。错误或 finish 后不可复用该解码器。解析器不保存帧数据，不会把载荷换行符当作帧边界。当前没有时间码连续性检测、奇数尺寸 420 或高位深支持。

## CLI：文件与标准输入

需要 MoonBit 和 Node.js 22.3+。不需要第三方 npm 包。

    moon run cmd/inspect --target js -- two-frames.y4m
    moon build cmd/inspect --target js
    node _build/js/debug/build/cmd/inspect/inspect.js two-frames.y4m

用单个参数 - 读取二进制标准输入。标准输出为 NDJSON：完整的帧各产生一行，成功读到流尾才产生 summary。退出码 0 成功，1 输入格式错误，2 参数或 I/O 错误。若文件在末尾截断，之前的完整帧仍会输出，但不会有成功摘要。CLI 按 64 KiB 分块读取。仅限已列出的 Y4M 子集。

## 验证与基准

    moon test --target wasm-gc
    moon test --target js
    moon build cmd/inspect --target js
    python tests/cli.py
    python tests/ffmpeg_reference.py --ffmpeg ffmpeg

前两条在两个后端分别运行相同的 5 项核心测试；CLI 黑盒套件共 4 项。最后一项需要支持 lavfi 的 FFmpeg，可用 --ffmpeg 指定其可执行路径；该脚本仅依赖 Python 标准库。它生成多帧 420jpeg 视频，然后让 FFmpeg 解码为原始 YUV，独立比较每一帧的亮度范围、帧数、帧率和画面尺寸。

参考运行：Windows、Node.js 24.19.0、FFmpeg 7.1、MoonBit 2026-11-17，512×256 / 120 帧 / 23,593,738 字节；全部帧与独立基线相符。一次运行约 0.14 秒（含 Node 启动，不含 FFmpeg 生成与解码）；该数字仅用于复现，不是性能保证。

## 许可

本项目采用 [MIT License](LICENSE)。
