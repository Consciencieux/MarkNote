# Marknote 当前架构

- **ArkUI**：首页、Navigation、Tabs、TextArea、查找、文件菜单、主题、关于与开源许可证入口。
- **ArkTS 文档状态**：`Index.ets` 持有 `source`；文稿状态不存放到 Web。
- **文件系统**：`DocumentFiles` 实现 `.md/.markdown/.txt/.svg/.tex` 打开/保存/外部冲突保护；`LocalState` 管最近文稿与未保存草稿。
- **ArkWeb**：只渲染安全的离线 HTML。`renderer/src/main.ts` 把 Markdown、SVG、TeX 数学排版统一到一个预览引擎，Web 侧不含导航、编辑器和任何原生操作按钮。
- **桥接**：单向 `WebviewController.runJavaScript('window.MarknotePreview.update(' + JSON.stringify(state) + ')')`，不向网页注册 ArkTS 接口。120ms 合并输入更新。
- **主题**：ArkUI 管主题，预览只接收 `system/light/dark` 的视觉偏好。
- **离线安全**：HTML 禁用原生 Markdown HTML，SVG 使用 DOMPurify 清理，KaTeX trust:false，CSP 禁止网络、插件、frame、表单，HAP 无联网权限。
- **分发合规**：renderer 构建从生产依赖收集 LICENSE/NOTICE，自动复制进 HAP，原生界面可查看。

SVG 渲染限静态安全图形；LaTeX 支持数学表达式和 KaTeX 支持的数学环境，
完整 `.tex` 编译（`documentclass`、宏包、PDF 输出）尚未实现。
