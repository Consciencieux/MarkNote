# HarmonyOS 应用市场发行准备

## 当前工程中已落实

- 应用导航、文件选取、读写、源码编辑、主题、关于页面均使用 ArkUI / ArkTS。
- Markdown、SVG、TeX 数学公式采用打包进 HAP 的离线 ArkWeb 渲染；没有网络权限或 CDN 请求。
- SVG 和 Markdown 标记经过严格的安全清理，预览页有内容安全策略。
- 使用许可友好的开源软件。DOMPurify 按 Apache-2.0 分支分发；KaTeX 字体按照 SIL OFL 1.1 单独声明。
- `renderer/npm run build` 从实际安装的生产依赖收集版权与许可全文，将其打包为应用可阅读的 `THIRD_PARTY_NOTICES.txt`；缺少许可证时中止构建。
- `EntryAbility` 以 singleton 注册了 Markdown、纯文本、SVG 和 TeX 的 `FileOpen`。文件管理器是否列出 Marknote，以及原地保存是否成功，仍须在目标设备上验收。

## 正式上架之前仍必须完成

1. 在 `renderer/` 执行 `npm install`、`npm run check`、`npm run build`，并将生成的 `package-lock.json` 纳入源码版本控制，后续使用 `npm ci` 重建相同依赖树。
2. 检查应用内「开源许可证与隐私说明」实际展示完整文本；复核传递依赖、NOTICE 与数学字体授权。
3. 使用 DevEco Studio 26 和目标 HarmonyOS 7 设备完成 HAP 编译、应用内打开/保存、文件管理器「打开方式」、只读另存为、外部修改拒绝覆盖、草稿恢复、主题与离线预览的真机验收。
4. 在应用市场材料中声明 `FileOpen`，以及 `general.markdown`、`general.plain-text`、`general.svg-image`、`org.tug.tex` / `general.tex`。完成该项审核后再把「可从文件管理器打开」写成已上架能力。
5. 替换测试包名、配置发行方拥有的签名与证书；不要使用他人的包名、商标或商店图片。
6. 根据发行主体及最终数据行为完成线上隐私政策，填入联系邮箱、政策 URL、生效日期，并与市场声明保持一致。
7. 完成应用市场实际要求的开发者实名认证、备案/资质、隐私安全、内容分级、测试截图及商店发布材料。

## 现阶段不应宣传的能力

- `.tex` 当前支持 TeX **数学排版**；完整 `\\documentclass` 文档/宏包/参考文献/PDF 编译依赖未来另一个正式引擎。
- SVG 只支持去掉脚本、动画和外链的安全静态子集；不提供 SVG JavaScript 交互或远程图片加载。
- 文件管理器打开和原地保存尚未在真机上验收，也没有应用市场 FileOpen 审核结论。

这些发行事项不是给项目添加内部兼容层，而是实际商业分发所需的外部边界。
