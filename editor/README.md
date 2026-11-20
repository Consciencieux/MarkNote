# 离线源码编辑器

本目录使用 CodeMirror 6 构建 MarkNote 的离线编辑器。正式文稿页通过受控消息端口同步文本；文件访问仍由 ArkTS 文稿服务负责。Markdown、SVG 和 LaTeX 分别使用 CodeMirror 的语言扩展，LaTeX 使用 `stex` 模式。Markdown 内嵌代码支持 JavaScript、TypeScript、Python、XML 和 LaTeX，其他语言保留原文。

在本目录运行 `npm ci`、`npm run check`、`npm test` 和 `npm run build`。构建生成 `entry/src/main/resources/rawfile/editor/index.html`，不加载网络资源；构建前还需安装 `renderer/` 的依赖，以生成完整第三方许可证声明。`tests/` 保留编辑同步的数据安全检查。

三折叠模拟器（API 26 Release）中，独立原型曾测得 64 KiB、512 KiB、2 MiB 和 8000000 字节 ASCII 文稿载入到下一帧分别为 55、39、68、214 ms；8000000 字节文稿一次输入事件到下一帧为 22 ms。这些是单次网页侧指标，不代表完整输入链路、峰值内存或全部语法解析性能。正式页面已在模拟器检查输入、分栏、撤销重做、查找替换、保存和滚动；日文输入法、RTL 及完整大文件性能矩阵尚未完成验证。
