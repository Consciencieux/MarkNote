# 功能目录

本文记录用户可以使用的功能、当前限制和主要代码位置。模块职责见[架构](ARCHITECTURE.md)，构建方法见[构建与贡献](../CONTRIBUTING.md)。

## 文稿与文件

| 功能 | 当前行为与限制 | 主要代码 |
| --- | --- | --- |
| 新建与打开 | 首页可新建 Markdown、纯文本、SVG 和 LaTeX 文稿，也可通过系统选择器打开文件。文件管理器可以通过系统文件关联打开受支持的文稿，默认进入预览。格式优先按文件后缀识别，其次使用系统声明的类型 | [HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)、[module.json5](../entry/src/main/module.json5) |
| 最近文稿 | 记录已获得持久化授权的文件。首页“全部”显示这些记录，不包含从未打开的文件。首页更多菜单支持按修改时间、最近打开、名称或类型排序，双栏打开文稿时仍可通过首页更多菜单调整列表排序。默认按文件修改时间倒序；无法获取修改时间的文件排在后面。打开文件不会改变修改时间，保存后刷新文件时间。临时授权文件不加入列表；长按或再次打开失败时可以移除记录，移除记录不会删除文件，收藏的文件仍保留在收藏中 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)、[RecentOrder.ts](../entry/src/main/ets/document/RecentOrder.ts)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |
| 收藏 | 预览和大纲标题栏、编辑和分栏的更多菜单可收藏或取消收藏具有持久授权的文件；首页“收藏”显示本机收藏。未保存或无法持久授权的文稿需要先保存或另存为。删除原文件后同步移除收藏；收藏只记录文件 URI，不复制文件 | [Index.ets](../entry/src/main/ets/pages/Index.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 保存与另存为 | 有写入授权时可保存到原 URI；原文件正文未变且没有未确认的写入时不重写文件。写入结果未确认时保留恢复正文及本次写入快照，并在离开时提示；原文件无法写入或保存失败时可另存为。另存成功后继续编辑新文件；授权未持久化时保存后会提示。写入前检查文件是否被外部修改，发现冲突时拒绝覆盖。有未保存修改时，先把完整编辑内容及保存基线写入私有恢复副本；恢复副本写入失败则停止写入目标文件。保存后重新读取并校验内容；文件提供方不保证写入操作具有原子性，恢复副本不等同于原文件字节级自动回滚 | [DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |
| 分享 | 预览和大纲标题栏、编辑和分栏的更多菜单可通过系统分享面板分享当前编辑内容，包括尚未保存的修改；分享文件为 UTF-8 临时副本，不修改原文件 | [DocumentShare.ets](../entry/src/main/ets/document/DocumentShare.ets)、[DocumentMenus.ets](../entry/src/main/ets/pages/DocumentMenus.ets) |
| 删除文件 | 已保存文稿可以在预览、大纲标题栏或编辑、分栏的更多菜单中请求移入系统回收站；删除前确认，未保存修改会明确提示。原文件发生外部变化、文件提供方不支持或授权不足时不删除，保留当前文稿及草稿；删除成功但草稿清理失败时保留文稿并提示。尚未保存为文件的文稿不能删除 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |
| 未保存内容 | 离开已修改的文稿前，应用询问是否保存。编辑时会在应用私有目录保存草稿，供异常退出后恢复；撤销回已保存内容、放弃修改或换成另一篇文稿时清除这份草稿。正常离开时也会清除草稿；清不掉，或清理期间又有新编辑且再次确认后仍清不掉，会留在文稿页并提示。冷启动先恢复该草稿；读取失败时保留副本，后续操作可重试。副本内容损坏时，用户可选择将原文件隔离保留在应用数据中并继续操作；隔离失败则不能覆盖原件。卸载应用会删除应用数据中的副本。若同时收到外部打开请求，先回到文稿页并确认离开，再打开外部文件 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)、[DraftCoordinator.ets](../entry/src/main/ets/document/DraftCoordinator.ets)、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 编码与换行 | 支持 UTF-8、UTF-16 LE/BE 和 GB18030，保存时保留原编码、BOM，以及 LF、CRLF 和 CR 换行。混合换行的文件在行数改变后不能直接按原方式保存；另存为时使用 LF。当前不能手动选择编码 | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets) |
| 文件大小 | 超过 8 MiB 的文件不能打开；保存后的编码字节超过 8 MiB 时拒绝写入。打开、保存、删除前读取和草稿使用异步文件接口。编码、摘要、大纲和查找计数仍在界面线程计算 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)、[DraftCoordinator.ets](../entry/src/main/ets/document/DraftCoordinator.ets) |

## 编辑与预览

| 功能 | 当前行为与限制 | 主要代码 |
| --- | --- | --- |
| 编辑 | 使用离线 CodeMirror 编辑 Markdown、LaTeX、SVG 和纯文本；按格式提供语法着色，纯文本不着色。Markdown 围栏支持 JavaScript、TypeScript、Python、XML 和 LaTeX；其他语言保持普通代码。LaTeX 使用 stex 模式，支持范围以该模式为准 | [DocumentCodeEditor.ets](../entry/src/main/ets/pages/DocumentCodeEditor.ets)、[languages.js](../editor/src/languages.js) |
| 快捷插入 | Markdown 编辑页提供标题、强调、链接、列表、待办、代码和公式等快捷操作；LaTeX 编辑页提供章节、小节、加粗、斜体、行内代码及公式快捷操作。工具栏位于顶部标题栏下方，空间不足时可横向滚动 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets) |
| 查找与替换 | 文稿菜单中的查找栏固定在顶部；编辑器获得键盘焦点时也可按 Ctrl+F 打开。查找栏打开后按字面文本统计匹配数，连续输入会合并后再更新。选择结果后显示当前位置，可在结果间前后跳转并替换单处。跳转和替换使用当时的正文。搜索词为空时隐藏结果导航；不支持正则表达式和全部替换 | [TextSearch.ets](../entry/src/main/ets/document/TextSearch.ets)、[DocumentAnalysis.ets](../entry/src/main/ets/document/DocumentAnalysis.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 文稿大纲 | Markdown 提取代码围栏以外的 ATX 标题，暂不解析 Setext 标题；打开大纲或停留在大纲页时按当前正文更新，输入过程中不逐字重算。LaTeX 使用预览解析得到的章节标题和源文本位置；只看大纲时不生成完整预览页面。两种格式共用分层大纲，可逐项展开、收起，并跳转到编辑位置。标题位置与当前正文不一致时不跳转 | [Document.ets](../entry/src/main/ets/model/Document.ets)、[DocumentAnalysis.ets](../entry/src/main/ets/document/DocumentAnalysis.ets)、[tex.ts](../renderer/src/renderers/tex.ts)、[DocumentOutlineView.ets](../entry/src/main/ets/pages/DocumentOutlineView.ets) |
| 撤销与重做 | CodeMirror 管理当前文稿的编辑历史；普通输入、工具栏插入及替换均可撤销。编辑和分栏复用同一历史，切换文稿时重置 | [editor-session.ts](../editor/src/editor-session.ts)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 页面与分栏 | 文稿默认打开预览，底部页签提供预览、编辑和大纲；不支持大纲的格式不显示大纲页签。当前没有显示的预览不排版。有底部导航避让区时，页签沿用组件对安全区的扩展，不再另加底边距。避让高度为 0 时（悬浮小窗是其中一种情况），页签栏与 `HdsTabs` 底边留出应用自己设定的 `sys.float.margin_left`，这不是华为规定的底部间距。文稿区域宽度达到 `WIDTH_LG` 断点时可分栏显示，预览在左、编辑在右；分栏显示时只更新这一侧的预览 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[DocumentPreviewView.ets](../entry/src/main/ets/pages/DocumentPreviewView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |

预览页面随应用离线打包。ArkUI 将格式、正文、主题、修订号和当前界面语言的预览提示传给网页；LaTeX 预览通过消息端口回传解析结果，网页不能调用文件或导航接口。内容安全策略禁止网络连接。Markdown 的网页链接由系统打开，不在预览页面中加载。

| 格式 | 预览方式 | 限制 |
| --- | --- | --- |
| `.txt` | 显示原文，保留换行和缩进 | 不解释 Markdown |
| `.md`、`.markdown` | 使用 markdown-it 渲染，支持表格、按语言着色的代码围栏、KaTeX 数学公式、SVG 代码围栏、Mermaid 图和只读待办复选框。文稿同目录及子目录中、系统允许读取的本地图片可以显示 | 不解析原始 HTML，不加载网络图片。预览中的待办不能修改文稿。http 和 https 链接点击后由系统打开，预览页面不加载网页；其他协议、带凭据的地址和相对路径只保留文字。绝对路径、逃出文稿目录的路径，以及未授权或打不开的图片保留占位文字，不影响打开文稿。图片按阅读位置加载，单张文件超过 32 MiB 时保留占位；支持 png、jpeg、gif、webp、bmp 和 svg。Mermaid 使用 11.16 画成 SVG，布局为 Dagre。指定 elk 或其他未注册布局时，该图显示预览错误。节点中的 HTML、点击回调和跳转链接不会保留。架构图图标需要联网，这里不加载。图内数学公式不保证排成 KaTeX。单图文本上限为 50000 个字符。代码围栏使用 highlight.js 11.12 的 latex、markdown、xml、json、javascript、typescript、python、bash、yaml、css、c、cpp、java。主要别名有 tex、md、html、js、ts、arkts、py、sh、shell、yml、c++、cxx、cc。ArkTS 按 TypeScript 规则着色，Shell 按 Bash 规则着色，不保证覆盖对应方言。代码围栏先显示转义后的原文，再由离线 Worker 按顺序着色；没有语言标记、text、plaintext、未注册语言，或 Worker 不可用、着色失败时，保留完整原文，不自动识别语言，也不截断。svg 围栏仍画成图形，mermaid 仍画成图，math 仍用 KaTeX。独立 .tex 预览不使用这套着色；编辑器使用独立语法引擎 |
| `.svg` | 使用 DOMPurify 清理后显示静态 SVG | 不执行脚本和动画，不加载外部资源；部分内部片段引用可用 |
| `.tex` | MyST 转换常见 LaTeX 文稿，KaTeX 渲染公式；无标记内容按正文显示，公式可使用数学定界符或受支持的独立公式命令 | 不执行 TeX 引擎或编译 PDF；宏包、命令和环境仅支持转换器已实现的部分，不支持的内容可能被省略；TikZ 尚未接入 |

预览入口是 [main.ts](../renderer/src/main.ts)，各格式的实现位于 [renderer/src/renderers](../renderer/src/renderers/)。

## 设置与导航

应用文字、编辑器及预览正文的字号跟随系统字体大小设置。

设置从首页或文稿页的更多菜单进入。外观提供跟随系统、浅色和深色三个选项，偏好保存在本机；代码高亮提供关闭、GitHub、Atom One 和 Visual Studio 配色，编辑器及 Markdown 代码预览共享语法颜色，配色不改变代码框背景与布局。设置页还提供使用帮助、问题与建议、隐私说明和关于。问题与建议通过系统邮件应用发送至 zhouyi1227@outlook.com；未安装邮件应用时可直接使用该地址。语言可跟随系统，也可指定简体中文、繁体中文、藏文、英文、日文、韩文、俄文、阿拉伯文或维吾尔文，选择后立即生效。跟随系统排在最前，其余语言按汉语拼音排列。跟随系统时，未提供的系统语言显示简体中文。阿拉伯文和维吾尔文从右向左排列；未单独指定语言时，排列方向跟随系统语言。

文稿列表与文稿以双栏显示时，可通过文稿标题栏放大文稿或恢复文稿列表；文稿菜单可关闭当前文稿。放大期间窗口宽度发生变化时，恢复由系统自动选择单栏或双栏；单栏时显示返回按钮。预览和编辑并排的分栏页签按文稿区域宽度提供。

“关于”页显示应用名称、版本，提供 GitHub 项目主页和开源许可证入口；主页交给系统浏览器打开。开源许可证页分别提供本项目和第三方许可证全文。页面先打开，再读取并按段显示原文，不删减许可证内容。使用帮助可从设置页直接打开，支持离线查看。

标题栏使用 HDS 导航组件，菜单使用系统菜单组件。文稿标题栏显示文件名，不显示行数、字符数或保存状态。菜单在高、中材质等级使用沉浸材质，在低材质等级或能力查询失败时关闭菜单材质并使用系统默认背板，以避免菜单内容与正文重叠。

主要代码：[SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)、[SettingsPage.ets](../entry/src/main/ets/pages/SettingsPage.ets)、[MenuMaterialOptions.ets](../entry/src/main/ets/pages/MenuMaterialOptions.ets)。

## 公共滚动行为

首页和设置页使用原生 `List`；文稿页签和分栏使用 `DocumentScrollLayer` 中的 `Scroll`。这些页面通过 `PageScrollPolicy` 共用边缘回弹、按需显示滚动条及安全区配置，同时各自持有滚动控制器。

标题栏在列表起点显示初始样式，内容向上滚动时由 HDS 渐变模糊。代码高亮设置页由分组标题提供首项留白。预览随原生容器滚动，编辑器在底部页签上方有独立视口，通过 ArkWeb 的嵌套滚动与原生容器衔接。

主要代码：[PageScrollPolicy.ets](../entry/src/main/ets/pages/PageScrollPolicy.ets)、[HdsMaterialStyles.ets](../entry/src/main/ets/pages/HdsMaterialStyles.ets)、[DocumentScrollLayer.ets](../entry/src/main/ets/pages/DocumentScrollLayer.ets)。
