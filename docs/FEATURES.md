# 功能目录

本文记录用户可以使用的功能、当前限制和主要代码位置。模块职责见[架构](ARCHITECTURE.md)，构建方法见[构建与贡献](../CONTRIBUTING.md)。

## 文稿与文件

| 功能 | 当前行为与限制 | 主要代码 |
| --- | --- | --- |
| 新建与打开 | 首页可新建 Markdown、纯文本、SVG 和 LaTeX 文稿，也可通过系统选择器打开文件。文件管理器可以通过系统文件关联打开受支持的文稿，默认进入预览。格式优先按文件后缀识别，其次使用系统声明的类型 | [HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)、[module.json5](../entry/src/main/module.json5) |
| 最近文稿 | 记录已获得持久化授权的文件。首页“全部”显示这些记录，不包含从未打开的文件。首页更多菜单支持按修改时间、最近打开、名称或类型排序，双栏打开文稿时仍可通过首页更多菜单调整列表排序。默认按文件修改时间倒序；无法获取修改时间的文件排在后面。打开文件不会改变修改时间，保存后刷新文件时间。临时授权文件不加入列表。长按可预览文稿行。系统启用触感反馈时，长按菜单弹出会振动。长按菜单提供分享、另存为、多选、收藏或取消收藏、移除记录和删除文件。删除前会确认。进入多选时选中长按的文稿，可继续点选或滑动选择，可在底部工具栏分享或移除记录，也可在“更多”中删除文件。另存副本只针对一篇文稿，通过系统保存选择器写入新文件，不修改原文件。移除记录不会删除文件，收藏的文件仍保留在收藏中。首页分享的是已保存内容，不含尚未保存的编辑 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)、[RecentOrder.ts](../entry/src/main/ets/document/RecentOrder.ts)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |
| 收藏 | 预览和大纲标题栏、编辑和分栏的更多菜单可收藏或取消收藏具有持久授权的文件；首页“收藏”显示本机收藏。未保存或无法持久授权的文稿需要先保存或另存为。删除原文件后同步移除收藏；收藏只记录文件 URI，不复制文件 | [Index.ets](../entry/src/main/ets/pages/Index.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 保存与另存为 | 有写入授权时可保存到原文件。正文和换行均与上次保存一致，且没有未确认的写入时，跳过重写。原文件被外部修改，或无法建立恢复副本时，停止覆盖。写入结果未确认时保留恢复内容，并在离开时提示。恢复副本可找回编辑内容，无法保证逐字节还原原文件。保存期间的新编辑仍算未保存修改。原文件无法写入或保存失败时可另存为，成功后继续编辑新文件。保存后若未取得持久授权会提示 | [DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |
| 分享 | 预览和大纲标题栏、编辑和分栏的更多菜单可通过系统分享面板分享当前编辑内容，包括尚未保存的修改；分享文件为 UTF-8 临时副本，不修改原文件。首页长按或多项选择分享的是已保存文件的副本，不含尚未保存的编辑。后续分享时尝试清理超过七天的旧副本 | [DocumentShare.ets](../entry/src/main/ets/document/DocumentShare.ets)、[DocumentMenus.ets](../entry/src/main/ets/pages/DocumentMenus.ets) |
| 删除文件 | 已保存文稿可以在预览、大纲标题栏、编辑、分栏的更多菜单，以及首页长按或多选中请求移入系统回收站；删除前确认，未保存修改会明确提示。原文件发生外部变化、文件提供方不支持或授权不足时不删除，保留当前文稿及草稿；删除成功但草稿清理失败时保留文稿并提示。尚未保存为文件的文稿不能删除 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |
| 未保存内容 | 离开已修改的文稿前，应用询问是否保存。编辑时会在应用私有目录保存草稿，供异常退出后恢复；放弃修改、关闭或换篇时会清理草稿，清理失败则留在当前文稿并提示。冷启动先恢复该草稿；读取失败时保留副本，后续操作可重试。副本内容损坏时，用户可选择将原文件隔离保留在应用数据中并继续操作；隔离失败则不能覆盖原件。卸载应用会删除应用数据中的副本。若同时收到外部打开请求，先回到文稿页并确认离开，再打开外部文件 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)、[DraftCoordinator.ets](../entry/src/main/ets/document/DraftCoordinator.ets)、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 编码与换行 | 支持 UTF-8、UTF-16 LE/BE 和 GB18030，保存时保留原编码、BOM，以及 LF、CRLF 和 CR 换行。混合换行按编辑位置保留。新插入的换行沿用所在行的格式，末行沿用前一个换行。有 BOM 时按标记严格解码，指定其他编码或文件内容无效时会提示失败。无 BOM 时自动识别，无法解码可在打开时手选编码。已打开的文稿若显示乱码，处理未保存修改后可从菜单按编码重新打开，原文件保持原样 | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets) |
| 文件大小 | 支持打开、保存和恢复超过 8 MiB 的文稿，实际大小受可用内存影响。保存还需要足以容纳编码后文稿的临时存储空间 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)、[DraftCoordinator.ets](../entry/src/main/ets/document/DraftCoordinator.ets) |

## 编辑与预览

| 功能 | 当前行为与限制 | 主要代码 |
| --- | --- | --- |
| 编辑 | 使用离线 CodeMirror 编辑 Markdown、LaTeX、SVG 和纯文本；按格式提供语法着色，纯文本不着色。Markdown 代码围栏与预览支持相同的语言标记；未指定或未识别的语言保持普通代码。LaTeX 使用 stex 模式，支持范围以该模式为准 | [DocumentCodeEditor.ets](../entry/src/main/ets/pages/DocumentCodeEditor.ets)、[languages.js](../editor/src/languages.js) |
| 快捷插入 | Markdown 编辑页提供标题、强调、链接、列表、待办、代码和公式等快捷操作；LaTeX 编辑页提供章节、小节、加粗、斜体、行内代码及公式快捷操作。工具栏位于顶部标题栏下方，空间不足时可横向滚动 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets) |
| 查找与替换 | 文稿菜单中的查找栏固定在顶部；编辑器获得键盘焦点时也可按 Ctrl+F 打开。查找栏按字面文本统计匹配数。选择结果后显示当前位置，可在结果间前后跳转并替换单处。跳转和替换使用当时的正文。搜索词为空时隐藏结果导航；不支持正则表达式和全部替换 | [TextSearch.ets](../entry/src/main/ets/document/TextSearch.ets)、[DocumentAnalysis.ets](../entry/src/main/ets/document/DocumentAnalysis.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 文稿大纲 | Markdown 提取代码围栏以外的 ATX 标题，暂不解析 Setext 标题；LaTeX 大纲显示可识别的章节。点大纲箭头展开或收起子级，点标题跳到编辑位置。使用读屏时，两项操作可分别聚焦，末级标题只有跳转入口。标题位置与当前正文不一致时不跳转 | [Document.ets](../entry/src/main/ets/model/Document.ets)、[DocumentAnalysis.ets](../entry/src/main/ets/document/DocumentAnalysis.ets)、[tex.ts](../renderer/src/renderers/tex.ts)、[DocumentOutlineView.ets](../entry/src/main/ets/pages/DocumentOutlineView.ets) |
| 撤销与重做 | CodeMirror 管理当前文稿的编辑历史；普通输入可撤销，每次工具栏插入或单处替换可单独撤销。编辑和分栏复用同一历史，切换文稿时重置 | [editor-session.ts](../editor/src/editor-session.ts)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 页面与分栏 | 文稿默认打开预览，底部页签提供预览、编辑和大纲；不支持大纲的格式不显示大纲页签。文稿区域足够宽时，左侧实时预览与右侧编辑等宽显示 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[DocumentPreviewView.ets](../entry/src/main/ets/pages/DocumentPreviewView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |

各格式均可离线预览。

编辑器按源码行、预览按正文段落自动确定文字方向。同一文稿可以同时包含从右向左和从左向右的段落；应用语言决定界面布局方向。

| 格式 | 预览方式 | 限制 |
| --- | --- | --- |
| `.txt` | 显示原文，保留换行和缩进 | 不解释 Markdown |
| `.md`、`.markdown` | 表格、任务列表、本地图片、代码围栏、公式和图表 | 任务列表只读。原始 HTML 和网络图片不渲染 |
| `.svg` | 使用 DOMPurify 清理后显示静态 SVG | 不执行脚本和动画，不加载外部资源；部分内部片段引用可用 |
| `.tex` | MyST 转换常见 LaTeX 文稿，KaTeX 渲染公式，TikZ Editor Core 绘制简单的 TikZ 图；无标记内容按正文显示，公式可使用数学定界符或受支持的独立公式命令 | 不执行 TeX 引擎或编译 PDF；正文只显示转换器支持的宏包、命令和环境 |

预览入口是 [main.ts](../renderer/src/main.ts)，各格式的实现位于 [renderer/src/renderers](../renderer/src/renderers/)。

### Markdown 预览

- **本地图片。** 可显示文稿目录及子目录中已授权的 PNG、JPEG、GIF、WebP、BMP 和 SVG。图片随阅读位置加载，大图适应栏宽，原图保留。多帧 GIF 和 WebP 可播放。绝对路径、越出文稿目录、无权读取或无法解码的图片显示占位文字。
- **网页链接。** 点击 HTTP 或 HTTPS 链接，系统会打开完整地址。带凭据的链接、其他协议和相对链接只显示文字。
- **代码高亮。** 支持 LaTeX、Markdown、XML、JSON、JavaScript、TypeScript、Python、Bash、YAML、CSS、C、C++ 和 Java。ArkTS 按 TypeScript、Shell 按 Bash 着色。未指定语言、标为纯文本、语言未知或着色失败时，保留完整原文。所有可用标记见[语言别名表](../shared/code-languages.ts)。
- **图形与公式。** `svg`、`math` 和 `mermaid` 围栏分别显示图形、公式和图表。Mermaid 使用 Dagre 布局，指定 ELK 等未注册布局时该图会报错。每幅图的源码上限为 50,000 个字符。图内不加载在线图标，不保留 HTML 标签、点击回调和跳转链接，数学公式的排版支持有限。

### LaTeX 预览

打开 `.tex` 文件可预览正文中的 `tikzpicture`，包括放在 `figure` 等正文环境中的图。预览支持线段、箭头、圆、矩形及带文字的节点。请将图放在数学环境外，图中文字以普通文本显示。导言区的自定义定义和图中的外部文件不会加载。每幅图的源码上限为 50,000 个 UTF-16 代码单元。无法绘制的图显示提示和原始源码。完整编译可在电脑上进行。[TikZ 示例](../examples/tikz.tex)

## 设置与导航

应用文字、编辑器及预览正文的字号跟随系统字体大小设置。使用读屏时，外观、语言和高亮配色可整行聚焦、双击选择，应用向系统提供当前选中状态。

设置从首页或文稿页的更多菜单进入。外观提供跟随系统、浅色和深色三个选项，偏好保存在本机；代码高亮提供关闭、GitHub、Atom One 和 Visual Studio 配色，编辑器及 Markdown 代码预览共享语法颜色，配色不改变代码框背景与布局。设置页还提供使用帮助、问题与建议、隐私说明和关于。问题与建议通过系统邮件应用发送至 zhouyi1227@outlook.com；未安装邮件应用时可直接使用该地址。语言可跟随系统，也可指定简体中文、繁体中文、藏文、英文、日文、韩文、俄文、阿拉伯文或维吾尔文，切换后界面和预览提示随即更新。跟随系统排在最前，其余语言按汉语拼音排列。跟随系统时，港澳台中文默认使用繁体，显式指定简体时使用简体。未提供的系统语言显示简体中文。阿拉伯文和维吾尔文从右向左排列；未单独指定语言时，排列方向跟随系统语言。

文稿列表与文稿以双栏显示时，可通过文稿标题栏放大文稿或恢复文稿列表；文稿菜单可关闭当前文稿。放大期间窗口宽度发生变化时，恢复由系统自动选择单栏或双栏；单栏时显示返回按钮。

“关于”页显示应用名称、版本，提供 GitHub 项目主页和开源许可证入口；主页交给系统浏览器打开。开源许可证页分别提供本项目和第三方许可证全文。页面先打开，再读取并按段显示原文，不删减许可证内容。使用帮助可从设置页直接打开，支持离线查看。

“隐私说明”可离线阅读数据处理摘要，并可通过系统浏览器打开完整隐私政策。发布地址见[隐私说明文档](PRIVACY.md)。

文稿标题栏显示文件名，不显示行数、字符数或保存状态。菜单在高、中材质等级使用沉浸材质，在低材质等级或能力查询失败时关闭菜单材质并使用系统默认背板，以避免菜单内容与正文重叠。

主要代码：[SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)、[SettingsPage.ets](../entry/src/main/ets/pages/SettingsPage.ets)、[MenuMaterialOptions.ets](../entry/src/main/ets/pages/MenuMaterialOptions.ets)。

## 公共滚动行为

- **首页与设置。** 列表在起点时，首项位于标题栏下方。向上滚动后，内容可进入标题栏的渐变模糊区，滚到边缘时有回弹。切换首页“全部”和“收藏”会回到对应列表顶部。代码高亮设置页由“主题”分组标题提供首项间距。
- **文稿页。** 预览、编辑和大纲也随滚动显示标题栏模糊。正文可滚入底部悬浮页签的渐变区，滚到末尾时最后一行可移到页签上方。预览和编辑的系统纵向滑块支持鼠标拖动，滚到两端时随回弹压缩。编辑时键盘弹出或在文末连续换行，视口随光标滚动。
- **分栏。** 左侧预览和右侧源码独立滚动，各自显示滑块。两侧的页首和文末按同一标题栏与页签留出空间，正文两侧留有边距。

主要代码：[PageScrollPolicy.ets](../entry/src/main/ets/pages/PageScrollPolicy.ets)、[HdsMaterialStyles.ets](../entry/src/main/ets/pages/HdsMaterialStyles.ets)、[DocumentScrollLayer.ets](../entry/src/main/ets/pages/DocumentScrollLayer.ets)。
