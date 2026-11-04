# Marknote 当前架构

界面仍在 ArkUI。文稿格式不由页面自行判断扩展名，文稿会话也不再散落在页面里。

- **EntryAbility**：singleton。桌面启动进入首页；`ohos.want.action.viewData` 的文件请求交给 `LaunchRequests`。页面还没创建时先留住这一次请求，准备好后再打开，避免冷启动丢文件。
- **DocumentService**：当前文稿的身份、正文、格式、来源和修订状态。新建、选择器、最近文稿和系统打开都从这里进入。保存、另存为、草稿恢复和外部冲突也在这里决定。
- **FormatRegistry**：扩展名、UTD、MIME、默认文件名、大纲和快捷插入。文件名能对上已注册后缀时用文件名；否则用系统声明的类型。对不上的系统类型不会当成 Markdown。
- **TextEncoding**：把字节还原成编辑器用的 `\n` 文本，保存时写回原来的编码、BOM 和换行。支持 UTF-8、UTF-16 LE/BE 和 GB18030。写回后若字符对不上，拒绝写入。混合换行只在行数不变时按原样写回。
- **DocumentFiles**：选择、读取、按实际打开结果判断能否写入、持久授权、冲突检查和写回。冲突对比的是打开或上次保存时的 SHA-256 字节指纹。只读授权可以编辑，保存时走另存为。
- **界面**：首页是 `HdsNavigation`，文稿页是 `HdsNavDestination`。标题栏材质跟随系统。新建和打开留在首页内容里；保存、查找、更多使用系统符号。最近文稿、外观和许可证使用系统列表、菜单和半模态。编辑、预览、大纲和分栏仍由 `Tabs` 切换，宽度达到 720vp 才出现分栏。键盘避让是 `RESIZE_WITH_CARET`。这套组件还没有在真机上核对过外观。
- **ArkWeb**：`renderer/src/renderers/` 里按格式 ID 分开渲染 `plain`、`markdown`、`svg`、`tex-math`。页面只把格式 ID 和正文交给预览。120ms 合并更新保留。
- **桥接**：单向 `MarknotePreview.update`。预览页不注册 ArkTS 接口，也没有联网权限。

系统文件关联注册在 `module.json5`：`file` scheme、`FileOpen`，类型是 `general.markdown`、`general.plain-text`、`general.svg-image`、`org.tug.tex`。SDK 里的 TeX 统一类型是 `general.tex`，所以一并注册，避免文件管理器对不上。不注册 `general.file` 或 `general.text`。

SVG 仍去掉脚本、动画、外链和 `foreignObject`。内部 `url(#id)`、片段引用和 `data:` 图片保留。`.txt` 不再按 Markdown 排版。完整 TeX 文档编译还没有做。大文件的读写仍在主线程。分享到其他应用不在这次范围内。
