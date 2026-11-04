# MarkNote

MarkNote 是 HarmonyOS 上的本地文稿编辑器。界面、导航、编辑、查找、大纲和主题由 ArkUI 实现；ArkWeb 只负责渲染离线预览，不参与编辑。

## 支持的格式

| 格式 | 编辑 | 预览 |
| --- | --- | --- |
| `.md` `.markdown` | ArkUI TextArea | markdown-it 15.0.3，支持表格、代码围栏、KaTeX 公式和 `svg` 代码围栏 |
| `.txt` | ArkUI TextArea | 原样显示纯文本，保留空格、换行和缩进，不解释 Markdown |
| `.svg` | ArkUI TextArea | 经 DOMPurify 清理的静态 SVG，不含脚本、动画和外链 |
| `.tex` | ArkUI TextArea | KaTeX 0.19.1 数学表达式，不编译完整 TeX 文档 |

预览所需的 JavaScript、样式和数学字体都打包在 HAP 内，运行时不访问网络。

## 能做什么

首页可以新建文稿、通过系统文件选择器打开文件、恢复未保存的草稿，并列出最近文稿。系统文件管理器也能把上述四种文件交给 MarkNote，直接进入编辑页。

编辑页提供源码编辑、离线预览、Markdown 大纲、查找替换、保存和另存为；屏幕足够宽时可以分栏对照。文件读写支持 UTF-8、UTF-16 LE/BE 和 GB18030，保存时按原编码、BOM 和换行写回。写入前会比对字节指纹，以发现文件是否被外部修改。外观可以设为跟随系统、浅色或深色。

各项功能的具体边界和已知限制集中在 [docs/FEATURES.md](docs/FEATURES.md)。`examples/` 提供 Markdown、SVG 和 TeX 三种格式的示例文件，仅供对照，应用运行时不读取该目录。

## 文档

| 文件 | 内容 |
| --- | --- |
| [docs/FEATURES.md](docs/FEATURES.md) | 已接入的用户功能、实际限制与负责代码 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 模块职责与数据流向 |
| [docs/STRUCTURE.md](docs/STRUCTURE.md) | 目录与文件用途 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 环境、构建、签名与提交要求 |
| [docs/STORE_RELEASE.md](docs/STORE_RELEASE.md) | 上架前必须完成的事项 |
| [docs/PRIVACY.md](docs/PRIVACY.md) | 本机数据行为，以及发行者需要补齐的隐私政策字段 |
| [third_party/README.md](third_party/README.md) | 直接依赖及其许可证 |
| [AGENTS.md](AGENTS.md) | 修改代码时需要遵守的项目边界 |
