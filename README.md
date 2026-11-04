# Marknote

HarmonyOS 上的本地文稿编辑器。界面、导航、读写、编辑、查找、大纲和主题都在 ArkUI；ArkWeb 只负责离线预览。

## 格式

| 格式 | 编辑 | 预览 |
| --- | --- | --- |
| `.md` `.markdown` | 原生 TextArea | markdown-it 15.0.3。含表格、代码围栏，以及 `$...$` / `$$...$$` / `\(...\)` / `\[...\]` 公式和 `svg` 围栏 |
| `.txt` | 原生 TextArea | 纯文本。保留空格、换行和缩进，不解释 Markdown |
| `.svg` | 原生 TextArea | 经 DOMPurify 清理的静态 SVG。没有脚本、动画、外链或外部资源 |
| `.tex` | 原生 TextArea | KaTeX 0.19.1 数学表达式。没有完整 TeX 文档编译 |

数学插件是 `@mdit/plugin-katex` 1.1.4。预览依赖、样式和数学字体打进 HAP，不从网络获取。

首页可以新建、打开、恢复草稿，并列出最近文稿。编辑页有源码、预览、大纲、查找替换、保存、另存为，宽屏时可以分栏。文件保持原来的 UTF-8 BOM 和换行；若磁盘内容在打开后被其他应用改过，保存会拒绝覆盖。主题可以跟随系统、浅色或深色。

`examples/` 里有三种格式的示例。

## 当前做不到的事

- `.tex` 不能处理 `\documentclass`、宏包或 PDF 编译。
- SVG 不是交互图形，带外部链接的图不会完整显示。
- 文本框没有多光标和语法折叠。

## 别处的说明

| 文件 | 内容 |
| --- | --- |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 环境、构建、签名和提交 |
| [AGENTS.md](AGENTS.md) | 改代码时要守住的约束 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 模块怎么分工 |
| [docs/STORE_RELEASE.md](docs/STORE_RELEASE.md) | 上架前还要做的事 |
| [docs/PRIVACY.md](docs/PRIVACY.md) | 本机数据行为，以及发行者要补的隐私政策字段 |
| [third_party/README.md](third_party/README.md) | 直接依赖和许可证选择 |
