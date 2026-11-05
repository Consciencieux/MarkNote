# 功能目录

本页登记已经接入用户入口的功能、当前边界和负责代码。尚未接通用户入口的设计留在 Issue 等任务渠道，不在此登记。模块分工见 [ARCHITECTURE.md](ARCHITECTURE.md)，构建方式见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 文稿与文件

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 首页与新建 | 首页是大标题为「文稿」的 `HdsNavigation`。新建和打开入口放在页面内容区，不放在标题栏。新建时从菜单选择 Markdown、纯文本、SVG 或 LaTeX 公式，默认文件名和初始内容由格式决定 | [HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)（`HomeView`、`newDocumentMenu`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`startNew`）、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) |
| 最近文稿 | 本机保留最多 12 条记录，每条显示文件名和格式名。再次打开时尝试激活持久化授权，授权失效时提示重新选择文件 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`release`）、[HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)（`RecentRow`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`rememberRecent`） |
| 选择文件打开 | 应用内使用系统 `DocumentViewPicker` 取得 URI。文件管理器也可通过 `viewData` / `FileOpen` 打开 `.md`、`.markdown`、`.txt`、`.svg` 和 `.tex`，并直接进入文稿页的预览。格式判断以文件后缀优先，其次使用系统声明的 UTD 或 MIME；两者都无法匹配时拒绝打开，不按 Markdown 渲染 | [module.json5](../entry/src/main/module.json5)、[EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`openUri`） |
| 保存与另存为 | 有写入授权时按原 URI 写回；只有读取授权或写入失败时改为另存为。保存后按字节指纹和正文再读校验。提供方不保证写入是原子操作 | [DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`save`）、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`write`） |
| 外部修改检查 | 写入前对比打开时或上次保存成功时的 SHA-256 字节指纹，不一致时拒绝覆盖，可改为另存为 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`write`） |
| 未保存保护与草稿恢复 | 离开文稿时，已保存过且有写权限的文件直接写回，不打断用户；只有新建未命名、只读或写回失败时才询问保存还是放弃。编辑期间延迟写入的应用私有草稿只用于异常退出兜底，正常离开即清除；下次启动发现草稿就直接接着编辑，首页不再有「未保存的文稿」入口 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`saveBeforeLeaving`、`closeToLibrary`、`scheduleRecovery`）、[DocumentBridge.ets](../entry/src/main/ets/pages/DocumentBridge.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`resumeDraft`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 文本编码与换行 | 读取 UTF-8、UTF-16 LE/BE 和 GB18030，记录 BOM 与换行方式并在保存时写回。写回后字符对不上时拒绝保存。混合换行只在行数不变时原样写回；行数变化时原地保存会被拒绝，另存为改用 LF。目前没有手动选择编码的界面 | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets) |
| 文件大小 | 超过 8 MiB 的文件拒绝读取。读写目前在 UI 线程同步执行 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |

## 编辑与工作区

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 源码编辑 | 使用 ArkUI `TextArea`，支持基础文本输入、光标和选区。切到编辑页签不主动弹键盘，点文字才弹；离开编辑页签退出编辑态。行数、字符数和保存状态显示在文稿页标题的副标题。没有多光标和语法折叠，也没有行级语法高亮 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`EditPage`、`updateSource`、`statusLine`、`stopEditing`） |
| 快捷插入 | Markdown 的标题、强调、链接、任务、代码围栏和公式从底部格式栏插入。格式栏是自绘的纯图标栏，只显示前四项，其余收进 `more` 菜单。其他格式没有快捷插入，不显示格式栏 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)（`InsertAction`、`inserts`）、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets)（`FormatBarView`、`barInserts`、`moreInserts`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`insertToken`） |
| 查找与替换 | 文稿页内按字面文本查找，命中处自动选中，可跳到下一处并替换单处。不支持正则和全部替换 | [TextSearch.ets](../entry/src/main/ets/document/TextSearch.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`FindBar`、`findNext`、`replaceMatch`） |
| Markdown 大纲 | 提取代码围栏以外的 ATX 标题，点击可跳到对应文本位置。尚未解析 Setext 标题 | [Document.ets](../entry/src/main/ets/model/Document.ets)（`documentOutline`）、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`headingsFor`） |
| 编辑、预览与分栏 | 文稿页是 `HdsNavDestination`，底部用 `HdsTabs` 切换。页签顺序是预览、编辑、大纲，打开文稿默认停在预览，与系统和同类应用「打开即阅读」一致。大纲页签只对声明支持大纲的格式出现，纯文本、SVG 和 LaTeX 没有这一项；宽度达到 720vp 时再增加编辑与预览分栏。底部页签开启 `barOverlap` 并配置 `systemMaterialEffect`，得到与系统「备忘录」一致的悬浮沉浸光感；材质等级按 `getSystemMaterialTypes()` 的结果自适应，不支持 IMMERSIVE 时降级为 SMOOTH。编辑区获得焦点时页签栏收起（`barHeight(0)`）、底部只留格式栏，软键盘收起后换回页签栏，所以底部始终只有一条栏。切到编辑页签不会主动弹键盘，只有点文字才弹（`enableKeyboardOnFocus(false)`）；离开编辑页签会退出编辑态，回来时光标和键盘都不会被带回来。格式栏的显隐跟随 `window.on('keyboardHeightChange')`，不用 `onBlur`；位置按键盘高度自己算（`Stack` 底部对齐 + `keyboardInset`），因为页面本身不随键盘压缩 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`WorkspacePage`、`floatingBar`、`pickMaterialLevel`、`bindKeyboard`、`applyKeyboardInset`、`stopEditing`、`splitTab`、`SplitPage`）、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets) |
| 撤销与重做 | 编辑缓冲的撤销和重做记录在内存里，连续输入在 600 ms 内合并成一步，最多 200 步，切换文稿时清空。标题栏的撤销和重做图标在对应方向没有历史时置为未使能（`isEnabled: false`，由 HDS 组件绘制置灰态） | [EditHistory.ets](../entry/src/main/ets/document/EditHistory.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`menuIcon`、`undo`、`redo`、`refreshHistoryState`） |
| 文稿页标题栏菜单 | 编辑态标题栏依次是撤销、重做、四宫格和保存勾，与系统「备忘录」编辑页一致。查找收进四宫格菜单，菜单里还有新建 Markdown、新建纯文本、新建 SVG、新建 LaTeX 公式、打开文件、另存为、返回文稿列表、设置和关于。保存使用 `checkmark`，不带圆圈 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)（`documentTitle`）、[DocumentMenus.ets](../entry/src/main/ets/pages/DocumentMenus.ets)（`DocumentMenuContent`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`afterMenu`） |
| 外观设置 | 四宫格菜单的「设置」打开底部半模态，其中的「外观」用胶囊类单选分段按钮切换跟随系统、浅色和深色，选中态以背景板高亮表示，不使用勾选图标。偏好保存在本机并同步到预览 | [SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)（`SettingsView`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`changeTheme`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[styles.css](../renderer/src/styles.css) |

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
| 启动与导航 | `EntryAbility` 为 singleton，加载 ArkUI 主页面，键盘避让跟随光标。首页是 `HdsNavigation`，文稿页是 `HdsNavDestination`。冷启动和热启动的文件请求共用 `LaunchRequests` | [EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`bindWideBreakpoint`、`presentOpened`）、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 离线预览 | 预览的 JavaScript、CSS 和 KaTeX 字体由 Vite 打包在本地。模块没有声明网络权限，预览页通过 CSP 禁止网络连接 | [index.html](../renderer/index.html)、[vite.config.ts](../renderer/vite.config.ts)、[module.json5](../entry/src/main/module.json5) |
| 第三方许可说明 | 四宫格菜单的「关于」打开半模态，读取构建生成的许可证全文并附上隐私说明。缺少生成资源时显示提示 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`openLegal`）、[LegalView.ets](../entry/src/main/ets/pages/LegalView.ets)、[generate-notices.mjs](../renderer/scripts/generate-notices.mjs) |

以上入口之外，MarkNote 不接收其他应用分享的内容；文件管理器的「打开方式」也只覆盖本页列出的四种文稿，不接管其他文件。
