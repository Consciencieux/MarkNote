# 上架准备

## 商店文案

应用中文名和英文名均为 MarkNote。

一句话简介：支持多种格式的文本编辑与预览

详细介绍：MarkNote 是一款支持多种文本格式的编辑器，可编辑和预览 Markdown 文档、LaTeX 数学公式、SVG 矢量图形及普通文本文件，支持直接打开、修改和保存本地文件。

## 代码中已落实

- 导航、文件选取、读写、源码编辑、主题和关于页面均使用 ArkUI / ArkTS。
- Markdown、SVG 和 TeX 数学公式由打包进 HAP 的离线 ArkWeb 渲染，没有网络权限，也不发起 CDN 请求。
- SVG 和 Markdown 标记经过安全清理，预览页配置了内容安全策略。
- 第三方依赖均采用许可友好的开源许可证。DOMPurify 按 Apache-2.0 分发，KaTeX 及其附带字体按该包的 MIT 声明收录。
- `renderer` 的构建从实际安装的生产依赖中收集版权与许可全文，缺少许可证时中止构建。
- `EntryAbility` 以 singleton 注册了 Markdown、纯文本、SVG 和 TeX 的 `FileOpen`。

## 上架前必须完成

1. 在 `renderer/` 执行 `npm ci`、`npm run check` 和 `npm run build`，确认 `package-lock.json` 与依赖一致。
2. 在设置中打开「本项目开源许可证」「第三方开源许可证」和「隐私说明」，确认全文显示完整；复核传递依赖、NOTICE 与数学字体授权。
3. 用 DevEco Studio 26 和目标 HarmonyOS 7 设备完成真机验收，覆盖 HAP 编译与安装、应用内打开与保存、文件管理器「打开方式」、只读授权下的另存为、外部修改拒绝覆盖、草稿恢复、外观切换和离线预览。
4. 在应用市场材料中声明 `FileOpen`，以及 `general.markdown`、`general.plain-text`、`general.svg-image`、`org.tug.tex` 和 `general.tex`。审核完成前，不要宣称可以从文件管理器打开。
5. 配置发行方自己的签名与证书，替换测试用包名，不要使用他人的包名、商标或商店图片。
6. 根据发行主体和最终数据行为完成线上隐私政策，填入联系邮箱、政策 URL 和生效日期，并与市场声明保持一致。
7. 完成应用市场要求的开发者实名认证、备案或资质、隐私安全、内容分级和测试截图等发布材料。

各功能的实际限制见[功能目录](FEATURES.md)。上述事项属于商业分发的外部要求，不应通过在项目内添加兼容层来规避。
