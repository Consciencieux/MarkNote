# MarkNote

MarkNote 是 HarmonyOS 上的本地文稿编辑器。应用使用 ArkUI 提供导航和编辑功能，使用 ArkWeb 渲染离线预览。

## 功能

MarkNote 可以新建文稿，通过系统文件选择器或文件管理器打开文件，并保存或另存为。应用会记录最近文稿，并在异常退出后尝试恢复未保存的草稿。文稿页提供预览、源码编辑、查找替换，以及 Markdown 和 LaTeX 大纲；在宽屏设备上，还可以分栏显示编辑和预览。

| 格式 | 预览方式 |
| --- | --- |
| Markdown（`.md`、`.markdown`） | 渲染 Markdown、表格、代码围栏、数学公式和 SVG 代码围栏 |
| 纯文本（`.txt`） | 显示原文，保留空格、换行和缩进 |
| SVG（`.svg`） | 清理后显示静态图形 |
| LaTeX（`.tex`） | 预览常见文稿内容和数学公式，不执行 TeX 引擎或编译 PDF |

文件读写支持 UTF-8、UTF-16 LE/BE 和 GB18030。保存时保留原编码、BOM 和换行方式，并在写入前检查外部修改。详细行为和限制见[功能目录](docs/FEATURES.md)。

预览所需的脚本、样式和字体随应用打包；预览页面不访问网络。`examples/` 包含 Markdown、SVG 和 TeX 示例文件，供手动打开查看。

## 文档

- [功能目录](docs/FEATURES.md)：已实现的功能、限制和相关代码。
- [架构](docs/ARCHITECTURE.md)：模块职责与数据流。
- [仓库结构](docs/STRUCTURE.md)：目录、文件及常见改动的位置。
- [构建与贡献](CONTRIBUTING.md)：开发环境、构建验证和提交更改。
- [隐私说明](docs/PRIVACY.md)与[上架准备](docs/STORE_RELEASE.md)：数据行为及发布前需要核对的事项。
- [第三方组件与许可证](third_party/README.md)：依赖、许可证和声明生成方式。
- [项目开发约定](AGENTS.md)：修改项目时需要遵守的边界。

## 许可证

MarkNote 采用 GNU General Public License v3.0（GPL-3.0-only）。

Copyright (C) 2026 Zhou Yi. 详见 [LICENSE](LICENSE)。
