# 第三方组件与许可证

MarkNote 在本地打包的 ArkWeb 预览中使用第三方软件。这些代码、字体和商标归各自的上游作者所有，MarkNote 不主张其所有权，具体的分发条件由各自的许可证给出。

## 生成声明

在 `renderer/` 执行 `npm ci && npm run build` 即可生成声明。该命令从实际安装的生产依赖图中收集全部 LICENSE 和 NOTICE，写入 `entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt`。应用在四宫格菜单的「关于」里展示这份全文。

遇到未知许可证类型或缺少许可证文件时，构建会失败。KaTeX 字体单独授权：必须存在 `OFL.txt` 并完整附上，文件缺失或者不是 SIL Open Font License 时同样失败。

## 直接依赖

| 组件 | 固定版本 | 许可证 | 上游 |
| --- | --- | --- | --- |
| markdown-it | 15.0.3 | MIT | https://github.com/markdown-it/markdown-it |
| @mdit/plugin-katex | 1.1.4 | MIT | https://github.com/mdit-plugins/mdit-plugins |
| KaTeX 代码 | 0.19.1 | MIT | https://github.com/KaTeX/KaTeX |
| KaTeX 数学字体（随 KaTeX 附带） | 0.19.1 | SIL OFL-1.1 | 安装在 npm 包内的 `katex/dist/fonts/OFL.txt` |
| DOMPurify | 3.4.17 | Apache-2.0 或 MPL-2.0，本项目选用 Apache-2.0 | https://github.com/cure53/DOMPurify |

构建工具（Vite、TypeScript、vite-plugin-singlefile）不会打进 HAP。运行时传递依赖由安装后的包图确定，其许可证文本同样包含在生成的声明中。发布时不要用手写的说明替换这份生成结果。

应用图标为本仓库新绘制，未使用第三方素材。商店图片、翻译文案、用户导入的文稿，以及后续可能加入的主题或字体资源，如果随应用分发，需要单独确认权利。
