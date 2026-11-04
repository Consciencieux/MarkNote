# Marknote 当前架构

界面仍在 ArkUI。文稿格式不由页面自行判断扩展名。

- **FormatRegistry**：扩展名、默认文件名、是否有大纲、快捷插入、选择器过滤。新增格式先加在这里。
- **DocumentService**：按文件名取出格式，并决定要不要生成 Markdown 大纲。
- **TextEncoding**：把字节还原成编辑器用的 `\n` 文本，保存时写回原来的编码、BOM 和换行。支持 UTF-8、UTF-16 LE/BE 和 GB18030。混合换行在行数不变时按原样写回。
- **DocumentFiles**：选择、读取、冲突检查和写回。授权持久化仍在这里。
- **ArkWeb**：`renderer/src/renderers/` 里按格式 ID 分开渲染 `plain`、`markdown`、`svg`、`tex-math`。页面只把格式 ID 和正文交给预览。120ms 合并更新保留。
- **桥接**：单向 `MarknotePreview.update`。预览页不注册 ArkTS 接口，也没有联网权限。

SVG 仍去掉脚本、动画、外链和 `foreignObject`。内部 `url(#id)`、片段引用和 `data:` 图片保留。`.txt` 不再按 Markdown 排版。完整 TeX 文档编译还没有做。大文件的读写仍在主线程。
