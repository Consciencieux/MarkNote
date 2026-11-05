# 功能目录

本页登记已经接入用户入口的功能、当前边界和负责代码。尚未接通用户入口的设计留在 Issue 等任务渠道，不在此登记。模块分工见 [ARCHITECTURE.md](ARCHITECTURE.md)，构建方式见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 文稿与文件

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 首页与新建 | 首页是 `HdsNavigation` 的一级页面，`MINI` 标题栏（56vp），主标题「全部」与右侧菜单同一行。标题栏不配置 `style`，用组件默认值：`COMMON_BLUR` 下背板默认透明、随滚动浮出模糊蒙板与分割线，标题和菜单悬浮在内容之上。内容区只有新建/打开两个按钮和最近文稿列表，列表用系统间距资源（项距 `sys.float.padding_level6`、左右 `sys.float.margin_left` / `margin_right`）、`clip(false)` 让内容穿到标题栏下方。页面里不写标语、分组标题和空列表提示。新建和打开入口放在页面内容区，不放在标题栏。新建时从菜单选择 Markdown、纯文本、SVG 或 LaTeX 公式，默认文件名和初始内容由格式决定 | [HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)（`HomeView`、`newDocumentMenu`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`homeTitle`、`startNew`）、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) |
| 最近文稿 | 本机保留最多 12 条记录，每条显示文件名和格式名。再次打开时尝试激活持久化授权，授权失效时提示重新选择文件 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`release`）、[HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)（`RecentRow`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`rememberRecent`） |
| 选择文件打开 | 应用内使用系统 `DocumentViewPicker` 取得 URI。文件管理器也可通过 `viewData` / `FileOpen` 打开 `.md`、`.markdown`、`.txt`、`.svg` 和 `.tex`，并直接进入文稿页的预览。格式判断以文件后缀优先，其次使用系统声明的 UTD 或 MIME；两者都无法匹配时拒绝打开，不按 Markdown 渲染 | [module.json5](../entry/src/main/module.json5)、[EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`openUri`） |
| 保存与另存为 | 有写入授权时按原 URI 写回；只有读取授权或写入失败时改为另存为。保存后按字节指纹和正文再读校验。空文稿同样可以保存（空内容的指纹取固定摘要，不走 MD 的空数据更新）。提供方不保证写入是原子操作 | [DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`save`）、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`write`） |
| 外部修改检查 | 写入前对比打开时或上次保存成功时的 SHA-256 字节指纹，不一致时拒绝覆盖，可改为另存为 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`write`） |
| 未保存保护与草稿恢复 | 离开文稿时，已保存过且有写权限的文件直接写回，不打断用户；只有新建未命名、只读或写回失败时才询问保存还是放弃。确认用固定样式的 `AlertDialog`（文档对它的场景说明包含「取消编辑」），三个按钮为保存/放弃修改/取消，按钮颜色不手写，取 `DialogButtonStyle` 的默认值（`DEFAULT` 白底蓝字），保存项标 `HIGHLIGHT`。编辑期间延迟写入的应用私有草稿只用于异常退出兜底，正常离开即清除；下次启动发现草稿就直接接着编辑，首页不再有「未保存的文稿」入口 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`saveBeforeLeaving`、`askSaveOrDiscard`、`closeToLibrary`、`scheduleRecovery`）、[DocumentBridge.ets](../entry/src/main/ets/pages/DocumentBridge.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`resumeDraft`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 文本编码与换行 | 读取 UTF-8、UTF-16 LE/BE 和 GB18030，记录 BOM 与换行方式并在保存时写回。写回后字符对不上时拒绝保存。混合换行只在行数不变时原样写回；行数变化时原地保存会被拒绝，另存为改用 LF。目前没有手动选择编码的界面 | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets) |
| 文件大小 | 超过 8 MiB 的文件拒绝读取。读写目前在 UI 线程同步执行 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |

## 编辑与工作区

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 源码编辑 | 使用 ArkUI `TextArea`，支持基础文本输入、光标和选区。切到编辑页签不主动弹键盘，点文字才弹；离开编辑页签退出编辑态。行数、字符数和保存状态显示在文稿页标题的副标题。没有多光标和语法折叠，也没有行级语法高亮 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`EditPage`、`updateSource`、`statusLine`、`stopEditing`） |
| 快捷插入 | Markdown 的标题、强调、链接、任务、代码围栏和公式从编辑页格式栏插入。格式栏用 HDS `HdsActionBar` 和 `ActionBarButton`；无主按钮时将操作放入 `startButtons`，图标尺寸、按钮样式和背板使用组件默认值。其他格式没有快捷插入，不显示格式栏 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)（`InsertAction`、`inserts`）、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets)（`FormatBarView`、`actionButtons`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`insertToken`） |
| 查找与替换 | 文稿页内按字面文本查找，命中处自动选中，可跳到下一处并替换单处。不支持正则和全部替换 | [TextSearch.ets](../entry/src/main/ets/document/TextSearch.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`FindBar`、`findNext`、`replaceMatch`） |
| Markdown 大纲 | 提取代码围栏以外的 ATX 标题，按标题级别交给 ArkUI `TreeView` 显示可展开、折叠的层级；点击标题可跳到对应文本位置。尚未解析 Setext 标题 | [Document.ets](../entry/src/main/ets/model/Document.ets)（`documentOutline`）、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`headingsFor`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`updateHeadings`、`OutlinePage`） |
| 编辑、预览与分栏 | 文稿页是 `HdsNavDestination`，底部用 `HdsTabs` 切换，页签顺序为预览、编辑、大纲，打开文稿默认停在预览。大纲页签只对声明支持大纲的格式出现；ArkUI 典型 `WIDTH_LG` 断点从 840vp 起，达到后增加编辑与预览分栏。分栏用 ArkUI `RowSplit` 提供系统分隔线，保留其默认不可拖动行为。底部页签使用 HDS 悬浮样式，不覆写间距、蒙层或材质参数。编辑区用 `TextArea` 默认外观；切到编辑页签不会主动弹键盘，点文字才弹（`enableKeyboardOnFocus(false)`），离开编辑页签会退出编辑态 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`WorkspacePage`、`stopEditing`、`splitTab`、`SplitPage`、`updateHeadings`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`bindWideBreakpoint`）、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets) |
| 撤销与重做 | 编辑缓冲的撤销和重做记录在内存里，连续输入在 600 ms 内合并成一步，最多 200 步，切换文稿时清空。标题栏的撤销和重做图标在对应方向没有历史时置为未使能（`isEnabled: false`，由 HDS 组件绘制置灰态） | [EditHistory.ets](../entry/src/main/ets/document/EditHistory.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`menuIcon`、`undo`、`redo`、`refreshHistoryState`） |
| 文稿页标题栏菜单 | 标题栏提供撤销、重做、更多和保存入口；查找及新建、打开、另存为、返回文稿列表和设置位于更多菜单。标题栏由 HDS 导航组件绘制，图标交给系统符号资源 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`documentTitle`）、[DocumentMenus.ets](../entry/src/main/ets/pages/DocumentMenus.ets)（`DocumentMenuContent`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`afterMenu`） |
| 外观设置 | 设置 → 「外观」二级页用 `HdsListItemCard` 切换跟随系统、浅色和深色：左侧选项名，右侧 `SuffixRadio`，点整行或点单选框都可切换。选中态由主题取值直接决定，不存在一个都没选中的状态。偏好保存在本机并同步到预览 | [SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)（`SettingsView`、`themeLabel`）、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)（`SettingsDetail`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`changeTheme`、`Destination`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[styles.css](../renderer/src/styles.css) |

## 预览

文稿格式、默认文件名和选择器过滤条件由 [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) 统一定义。预览使用打包进应用的离线 ArkWeb 资源，ArkTS 只传入格式 ID 和正文。

| 格式 | 预览行为 | 限制 |
| --- | --- | --- |
| `.txt` | 原样显示普通文本，保留换行和缩进 | 不解释 Markdown |
| `.md`、`.markdown` | markdown-it 渲染标题、列表、表格和代码块，支持 KaTeX 数学公式和 `svg` 代码围栏 | 原始 HTML 不参与解析；外部图片不加载 |
| `.svg` | 经 DOMPurify 清理后显示静态 SVG，部分内部片段引用可用 | 脚本、动画和外部资源受限，安全规则仍需收紧 |
| `.tex` | KaTeX 渲染数学表达式及其支持的环境 | 不支持 `\documentclass`、宏包和完整 TeX 文档编译 |

共享预览入口在 [renderer/src/main.ts](../renderer/src/main.ts)，页面通过 `MarknotePreview.update` 接收内容和主题。

## 应用与分发

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 启动与导航 | `EntryAbility` 为 singleton，加载 ArkUI 主页面，键盘避让跟随光标。首页是 `HdsNavigation`，导航模式沿用组件默认 `Auto`；文稿页是 `HdsNavDestination`。冷启动和热启动的文件请求共用 `LaunchRequests` | [EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`bindWideBreakpoint`、`presentOpened`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 离线预览 | 预览的 JavaScript、CSS 和 KaTeX 字体由 Vite 打包在本地。模块没有声明网络权限，预览页通过 CSP 禁止网络连接 | [index.html](../renderer/index.html)、[vite.config.ts](../renderer/vite.config.ts)、[module.json5](../entry/src/main/module.json5) |
| 设置 | 四宫格菜单的「设置」进入 `HdsNavigation` 路由页，内容是一层导航列表：外观、隐私说明、第三方开源许可证、关于。每行使用 HDS `HdsListItemCard`，右侧状态和箭头分别使用 `SuffixTextAndArrow`、`SuffixArrow`；外观选项使用 `SuffixRadio`。卡片和列表间距沿用组件默认值。点进各自二级页，二级页从右侧推入同一个 `NavPathStack`。导航页和内容页都用小标题栏模式，页面底色由 `HdsNavDestination` 提供 | [SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)（`SettingsView`）、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)（`SettingsDetail`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`Destination`、`openSetting`） |
| 第三方许可说明 | 设置里的「第三方开源许可证」显示构建生成的许可证全文；「隐私说明」显示应用的本地化说明。缺少生成资源时显示提示 | [SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)（`SettingsDetail`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`openSetting`）、[generate-notices.mjs](../renderer/scripts/generate-notices.mjs) |

以上入口之外，MarkNote 不接收其他应用分享的内容；文件管理器的「打开方式」也只覆盖本页列出的四种文稿，不接管其他文件。
