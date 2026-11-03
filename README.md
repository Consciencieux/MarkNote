# Marknote · HarmonyOS 7 ArkUI 原生文稿编辑器

面向 HarmonyOS 应用市场分发的 **ArkUI 原生界面 + ArkTS 本地文档服务 + ArkWeb 离线排版引擎** 工程。
界面、系统导航、文件读写、编辑、查找、大纲、主题和关于页全部在 ArkUI；ArkWeb 仅承载预览内容。

## 已接入的格式

| 格式 | 输入与保存 | 预览引擎 | 当前语义 |
| --- | --- | --- | --- |
| `.md` `.markdown` `.txt` | 系统选择器 + 原生 TextArea | markdown-it 15.0.3 | Markdown、表格、代码围栏，`$...$`/`$$...$$`/`\\(...\\)`/`\\[...\\]` 数学公式、`svg` 代码围栏 |
| `.svg` | 原生 TextArea | SVG DOM + DOMPurify 3.4.17 | 安全静态 SVG 图形，禁用脚本、动画、外链与外部资源 |
| `.tex` | 原生 TextArea | KaTeX 0.19.1 | TeX 数学表达式与 KaTeX 数学环境；不包含完整文档编译或 TeX Live |

数学公式 Markdown 插件为 `@mdit/plugin-katex` 1.1.4。依赖代码、数学字体、样式随 HAP **离线打包**；不从任何 CDN 获取。

## 构建步骤

需要 DevEco Studio 26 / HarmonyOS SDK API 26、Node.js 22.12+（推荐 Node 24 LTS）和 npm。

```sh
cd renderer
npm install
npm run check
npm run build
```

`npm run build` 先生成单文件预览页，再收集实际安装的**运行时依赖**许可证和 NOTICE；
两个输出分别复制到：

```text
entry/src/main/resources/rawfile/preview/index.html
entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt
```

随后使用 DevEco Studio 打开仓库根目录，同步 OHPM，配置自己的应用包名和调试签名并运行/构建 HAP。
签名、开发者身份、商店发布资质和隐私政策地址不在仓库中伪造。

**本交付环境不具备 HarmonyOS SDK 或 npm 注册表访问能力**，因此这份 ZIP 包含完整 ArkTS 与 renderer 源码和构建脚本，**不包含生成的预览 HTML、许可证全集或已验证 HAP**。请先执行上面的 renderer 构建命令。真正上架前必须完成真机验证和商店审核材料。

## 应用功能

文稿首页提供新建 Markdown / SVG / LaTeX 数学文稿、打开、最近文稿和草稿恢复。
编辑页采用原生 Navigation 与 Tabs，包含源码编辑、离线预览、大纲、查找替换、保存、另存为和屏宽分栏。
文件保持 UTF-8 BOM/换行习惯，保存时阻止覆盖已在其他应用中修改的文件，并读回校验。
原生设置支持系统/浅色/深色；关于页可阅读随应用分发的第三方许可证全文与隐私说明。`examples/` 提供三种格式的本地示例，`docs/STORE_RELEASE.md` 说明商业上架前的必要条件。

## 版权及发布

`third_party/README.md` 列出了直接依赖与选用许可证：MIT 允许闭源商业发行；
DOMPurify 双许可选择 Apache-2.0 路径；**KaTeX 数学字体采用独立的 SIL OFL-1.1 许可**。
生成的应用内版权全文按实际安装运行时依赖计算，
包含传递依赖的许可证/NOTICE。没有额外购买商业授权的必要。

应用市场上线还需发行主体自行配置签名、商品信息、公开隐私政策 URL 和必要的资质。
`docs/PRIVACY.md` 提供当前本地数据行为说明，正式发布前需要填写主体和联络方式。

## 已知功能边界

- 目前没有完整 TeX 编译器。`.tex` 是 **数学公式输入与预览**，`\\documentclass`、`\\usepackage`、PDF 文档编译尚不可用。
- SVG 为静态安全子集，禁用内联脚本/交互、外链及外部资源，含外部链接的 SVG 不会完整呈现。
- `TextArea` 是基础原生文本编辑器，不具备 CodeMirror 的多光标和语法折叠。
- 这里没有调试签名、上架截图、HAP 真机验收报告，也没有宣称已经通过应用商店审核。
