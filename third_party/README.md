# 第三方组件与许可证

MarkNote 的离线预览使用下列第三方组件。各组件及附带资源的使用和分发条件以其上游许可证为准。

| 组件 | 版本 | 许可证 | 上游 |
| --- | --- | --- | --- |
| markdown-it | 15.0.3 | MIT | [markdown-it](https://github.com/markdown-it/markdown-it) |
| @mdit/plugin-katex | 1.1.4 | MIT | [mdit-plugins](https://github.com/mdit-plugins/mdit-plugins) |
| KaTeX 及其附带字体 | 0.19.1 | MIT | [KaTeX](https://github.com/KaTeX/KaTeX) |
| DOMPurify | 3.4.17 | Apache-2.0 或 MPL-2.0；本项目选择 Apache-2.0 | [DOMPurify](https://github.com/cure53/DOMPurify) |

## 应用内声明

按[构建与贡献](../CONTRIBUTING.md)中的预览构建步骤生成许可证文件。脚本从实际安装的生产依赖图中收集许可证和 NOTICE，写入 `entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt`；遇到未允许的许可证类型或缺少许可证文件时会中止构建。KaTeX 及其附带字体使用该包收录的 MIT 许可证声明。

应用通过“设置 → 开源许可证 → 第三方开源许可证”显示生成的声明；本项目的 GPL-3.0 许可证单独显示。Vite、TypeScript 和 vite-plugin-singlefile 用于构建，不打包到应用预览中。

应用图标由本仓库绘制。发布时应另行核对商店素材、翻译文案及其他随应用分发的资源的使用权。
