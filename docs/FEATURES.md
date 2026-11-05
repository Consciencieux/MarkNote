# 功能目录

本页登记已经接入用户入口的功能、当前边界和负责代码。尚未接通用户入口的设计留在 Issue 等任务渠道，不在此登记。模块分工见 [ARCHITECTURE.md](ARCHITECTURE.md)，构建方式见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 文稿与文件

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 首页与新建 | 首页是 `HdsNavigation` 的一级页面，`MINI` 标题栏（56vp），主标题「全部」与右侧菜单同一行。滚动及标题栏遵循下方「公共页面滚动」条目。内容区只有新建/打开两个按钮和最近文稿列表，列表用系统间距资源（项距 `sys.float.padding_level6`、左右 `sys.float.margin_left` / `margin_right`）。页面里不写标语、分组标题和空列表提示。新建和打开入口放在页面内容区，不放在标题栏。新建时从菜单选择 Markdown、纯文本、SVG 或 LaTeX 公式，默认文件名和初始内容由格式决定 | [HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)（`HomeView`、`newDocumentMenu`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`homeTitle`、`startNew`）、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) |
| 最近文稿 | 本机保留最多 12 条记录，每条显示文件名和格式名。再次打开时尝试激活持久化授权，授权失效时提示重新选择文件 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`release`）、[HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)（`RecentRow`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`rememberRecent`） |
| 选择文件打开 | 应用内使用系统 `DocumentViewPicker` 取得 URI。文件管理器也可通过 `viewData` / `FileOpen` 打开 `.md`、`.markdown`、`.txt`、`.svg` 和 `.tex`，并直接进入文稿页的预览。格式判断以文件后缀优先，其次使用系统声明的 UTD 或 MIME；两者都无法匹配时拒绝打开，不按 Markdown 渲染 | [module.json5](../entry/src/main/module.json5)、[EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`openUri`） |
| 保存与另存为 | 有写入授权时按原 URI 写回；只有读取授权或写入失败时改为另存为。保存后按字节指纹和正文再读校验。空文稿同样可以保存（空内容的指纹取固定摘要，不走 MD 的空数据更新）。提供方不保证写入是原子操作 | [DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`save`）、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`write`） |
| 外部修改检查 | 写入前对比打开时或上次保存成功时的 SHA-256 字节指纹，不一致时拒绝覆盖，可改为另存为 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`write`） |
| 未保存保护与草稿恢复 | 离开文稿时，只要正文和上次保存的内容不同，就弹出未保存确认，不因为文件可写就直接写回。问句是「是否保存更改？」。两个按钮水平排列，左「不保存」、右「保存」；只读文件右侧为「另存为」。两边都用 `DialogButtonStyle.DEFAULT`（白底蓝字，深色主题为黑底蓝字）。没有取消按钮，侧滑、返回键或点击遮罩会关掉弹窗并留在文稿。编辑期间延迟写入的应用私有草稿只用于异常退出兜底，正常离开即清除；下次启动发现草稿就直接接着编辑，首页不再有「未保存的文稿」入口 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`saveBeforeLeaving`、`askSaveOrDiscard`、`closeToLibrary`、`scheduleRecovery`）、[DocumentBridge.ets](../entry/src/main/ets/pages/DocumentBridge.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`resumeDraft`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 文本编码与换行 | 读取 UTF-8、UTF-16 LE/BE 和 GB18030，记录 BOM 与换行方式并在保存时写回。写回后字符对不上时拒绝保存。混合换行只在行数不变时原样写回；行数变化时原地保存会被拒绝，另存为改用 LF。目前没有手动选择编码的界面 | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets) |
| 文件大小 | 超过 8 MiB 的文件拒绝读取。读写目前在 UI 线程同步执行 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |

## 编辑与工作区

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 源码编辑 | 使用 ArkUI `TextArea`，支持基础文本输入、光标和选区。输入区背景透明并使用系统无圆角资源，与页面底色统一。切到编辑页签不主动弹键盘，点文字才弹；离开编辑页签退出编辑态。行数、字符数和保存状态显示在文稿页标题的副标题。没有多光标和语法折叠，也没有行级语法高亮 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`EditPage`、`updateSource`、`statusLine`、`stopEditing`） |
| 快捷插入 | Markdown 的标题、强调、链接、任务、代码围栏和公式从编辑页悬浮格式栏插入。格式栏用 HDS `HdsActionBar` 和 `ActionBarButton`；无主按钮时按官方指南将操作放入 `startButtons`，按钮、背板和自适应模糊交给组件默认实现。位置在设置中选择顶部、左侧或右侧；顶部和侧面都悬浮在全屏文稿层上。其他格式没有快捷插入，不显示格式栏 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)（`InsertAction`、`inserts`）、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets)（`FormatBarView`、`actionButtons`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`insertToken`、`documentTitle`、`WorkspacePage`）、[SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 查找与替换 | 文稿页内按字面文本查找，命中处自动选中，可跳到下一处并替换单处。不支持正则和全部替换 | [TextSearch.ets](../entry/src/main/ets/document/TextSearch.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`FindBar`、`findNext`、`replaceMatch`） |
| Markdown 大纲 | 提取代码围栏以外的 ATX 标题，按标题级别分层并可展开、折叠；点击标题可跳到对应文本位置。尚未解析 Setext 标题 | [Document.ets](../entry/src/main/ets/model/Document.ets)（`documentOutline`）、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`headingsFor`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`updateHeadings`、`visibleOutlineRows`、`OutlinePage`） |
| 编辑、预览与分栏 | 文稿页是 `HdsNavDestination`，底部用 `HdsTabs` 切换，页签顺序为预览、编辑、大纲，打开文稿默认停在预览。文稿各页签及分栏面板复用 `DocumentScrollLayer` 的 ArkUI `Scroll`；公共行为见「公共页面滚动」。为让父级 `Scroll` 统一承接滚动，预览使用 ArkWeb《Web组件大小自适应页面内容布局》的 `FIT_CONTENT` 并关闭 Web 自身过滚动；编辑 `TextArea` 不限高度以采用官方默认的内容自适应高度；大纲 `List` 不限高度并由外层滚动。HDS 标题栏按当前页签绑定对应的 `Scroller`。大纲页签只对声明支持大纲的格式出现；ArkUI 典型 `WIDTH_LG` 断点从 840vp 起，达到后增加编辑与预览分栏。分栏用 ArkUI `RowSplit` 提供系统分隔线，保留其默认不可拖动行为。点击切页保留 HdsTabs 对 `BottomTabBarStyle` 的默认动画时长。编辑区用透明 `TextArea` 和系统无圆角资源，与页面底色统一；切到编辑页签不会主动弹键盘，点文字才弹（`enableKeyboardOnFocus(false)`），离开编辑页签会退出编辑态 | [DocumentScrollLayer.ets](../entry/src/main/ets/pages/DocumentScrollLayer.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`WorkspacePage`、`stopEditing`、`splitTab`、`SplitPage`、`updateHeadings`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`bindWideBreakpoint`） |
| 撤销与重做 | 编辑缓冲的撤销和重做记录在内存里，连续输入在 600 ms 内合并成一步，最多 200 步，切换文稿时清空。标题栏的撤销和重做图标在对应方向没有历史时置为未使能（`isEnabled: false`，由 HDS 组件绘制置灰态） | [EditHistory.ets](../entry/src/main/ets/document/EditHistory.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`menuIcon`、`undo`、`redo`、`refreshHistoryState`） |
| 文稿页标题栏菜单 | 标题栏提供撤销、重做、更多和保存入口；查找及新建、打开、另存为、返回文稿列表和设置位于更多菜单。标题栏由 HDS 导航组件绘制，图标交给系统符号资源，按钮使用系统自适应沉浸材质。首页和文稿页的更多菜单及首页新建菜单共用材质配置：低算力或不支持沉浸材质的设备单独关闭菜单材质，使用系统默认背板；其余设备沿用应用级默认材质 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`documentTitle`）、[DocumentMenus.ets](../entry/src/main/ets/pages/DocumentMenus.ets)（`DocumentMenuContent`）、[MenuMaterialOptions.ets](../entry/src/main/ets/pages/MenuMaterialOptions.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`afterMenu`） |
| 外观设置 | 设置 → 「外观」二级页用 `HdsListItemCard` 切换跟随系统、浅色和深色：左侧选项名，右侧 `SuffixRadio`，点整行或点单选框都可切换。选中态由主题取值直接决定，不存在一个都没选中的状态。偏好保存在本机并同步到预览 | [SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)（`SettingsView`、`themeLabel`）、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)（`SettingsDetail`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`changeTheme`、`Destination`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[styles.css](../renderer/src/styles.css) |
| 编辑工具栏位置 | 设置 → 「编辑工具栏位置」可在顶部、左侧和右侧间选择。偏好保存在本机；只在支持快捷插入的格式和编辑/分栏页签显示 | [SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |

## 预览

文稿格式、默认文件名和选择器过滤条件由 [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) 统一定义。预览使用打包进应用的离线 ArkWeb 资源，ArkTS 只传入格式 ID 和正文。

| 格式 | 预览行为 | 限制 |
| --- | --- | --- |
| `.txt` | 原样显示普通文本，保留换行和缩进 | 不解释 Markdown |
| `.md`、`.markdown` | markdown-it 渲染标题、列表、表格和代码块，支持 KaTeX 数学公式和 `svg` 代码围栏 | 原始 HTML 不参与解析；外部图片不加载 |
| `.svg` | 经 DOMPurify 清理后显示静态 SVG，部分内部片段引用可用 | 脚本、动画和外部资源受限，安全规则仍需收紧 |
| `.tex` | KaTeX 渲染数学表达式及其支持的环境 | 不支持 `\documentclass`、宏包和完整 TeX 文档编译 |

共享预览入口在 [renderer/src/main.ts](../renderer/src/main.ts)，页面通过 `MarknotePreview.update` 接收内容和主题。

## 公共页面滚动

首页、设置首页及内容页、文稿预览/编辑/大纲及分栏共用 `PageScrollPolicy`。首页和设置保留原生 `List`，文稿使用 `DocumentScrollLayer`，各页面/页签的 Scroller 独立。

- 标题栏统一由 `scrollingTitleBar` 配置：HDS 组件安全区、固定渐变模糊及系统自适应按钮材质。保留官方 `GRADIENT_BLUR` 默认的 32vp 蒙层延伸，并以同一个常量给滚动容器配置顶部 `safeAreaPadding`，让初始内容避开额外蒙层。
- 文稿与设置采用相同的导航子页布局，不再由文稿页单独调用 `ignoreLayoutSafeArea` 扩展布局起点。`clipContent(SAFE_AREA)` 允许滚动内容进入避让区；文稿的 `HdsTabs` 和各 `TabContent` 都关闭默认裁剪，避免外层页签截断进入标题栏的内容。短文稿在 Scroll 中顶部对齐。
- 所有页面统一 `Spring` 边缘效果，短内容也能回弹。滚动条为系统按需显示 `Auto`，并使用 API 26 自动边距调整避让 padding、安全区和内容起止偏移；无滚动范围时不显示滚动条。
- 页面布局、滚动内容绘制和滚动条范围分别处理，不手绘模糊背板或滚动条。声明依据见代码中的官方文档链接。

负责代码：[PageScrollPolicy.ets](../entry/src/main/ets/pages/PageScrollPolicy.ets)、[HdsMaterialStyles.ets](../entry/src/main/ets/pages/HdsMaterialStyles.ets)、[DocumentScrollLayer.ets](../entry/src/main/ets/pages/DocumentScrollLayer.ets)、[SettingsPage.ets](../entry/src/main/ets/pages/SettingsPage.ets)。

## 应用与分发

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 启动与导航 | `EntryAbility` 为 singleton，加载 ArkUI 主页面，键盘避让跟随光标。首页是 `HdsNavigation`，导航模式沿用组件默认 `Auto`；文稿页是 `HdsNavDestination`。冷启动和热启动的文件请求共用 `LaunchRequests` | [EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`bindWideBreakpoint`、`presentOpened`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 离线预览 | 预览的 JavaScript、CSS 和 KaTeX 字体由 Vite 打包在本地。模块没有声明网络权限，预览页通过 CSP 禁止网络连接 | [index.html](../renderer/index.html)、[vite.config.ts](../renderer/vite.config.ts)、[module.json5](../entry/src/main/module.json5) |
| 设置 | 四宫格菜单的「设置」进入 `HdsNavigation` 路由页：外观与编辑工具栏位置为一组，隐私说明、开源许可证和关于为一组。「开源许可证」页分别进入本项目和第三方许可证；「关于」页提供 GitHub 项目主页，通过系统默认浏览器打开。首页、选项页和关于页共用系统分组卡片、列表行和分割线；选项由整行选择，当前项显示系统勾选标记。设置各级页面通过 `SettingsPage` 接入公共页面滚动配置，各路由分别持有并绑定自己的 Scroller。导航页和内容页都用小标题栏模式，页面底色由 `HdsNavDestination` 提供 | [SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)、[SettingsListRow.ets](../entry/src/main/ets/pages/SettingsListRow.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`Destination`、`openSetting`、`openProjectHome`） |
| 本项目开源许可证 | 设置 → 开源许可证 → 本项目开源许可证显示仓库根目录 `LICENSE` 的全文。这份文本是 GNU GPL-3.0，不并入第三方声明。缺少资源时显示提示 | [SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`openSetting`）、[generate-notices.mjs](../renderer/scripts/generate-notices.mjs) |
| 第三方许可说明 | 设置 → 开源许可证 → 第三方开源许可证显示构建生成的许可证全文；「隐私说明」显示应用的本地化说明。缺少生成资源时显示提示。第三方声明不包含本项目的 GPL | [SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)（`SettingsDetail`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`openSetting`）、[generate-notices.mjs](../renderer/scripts/generate-notices.mjs) |

以上入口之外，MarkNote 不接收其他应用分享的内容；文件管理器的「打开方式」也只覆盖本页列出的四种文稿，不接管其他文件。
