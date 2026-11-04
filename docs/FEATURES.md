# Marknote 功能目录

本目录供开发者查找**当前源码已接入的用户功能**及其负责位置。条目描述能够经现有应用入口触达的行为，并在同一处说明实际限制；不把功能设想、待办事项或发行进度登记为已实现功能。

这里记录的是**源码实现范围**，不附加真机验收或应用市场审核结论。实现原理与模块依赖见 [ARCHITECTURE.md](ARCHITECTURE.md)，构建及验证方式见 [CONTRIBUTING.md](../CONTRIBUTING.md)，发行事项见 [STORE_RELEASE.md](STORE_RELEASE.md)。

## 文稿与文件

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 首页与文稿创建 | 首页是 `HdsNavigation`，大标题为「文稿」。新建和打开留在页面内，不放进标题栏；新建由菜单选择 Markdown、纯文本、SVG、TeX。四宫格菜单进入「设置」和「关于」。默认名称与初始内容按格式确定 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`LibraryPage`、`startNew`）、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) |
| 文稿页标题栏菜单 | 编辑页标题栏显示保存和查找两个图标，四宫格菜单里依次是一级菜单项：新建 Markdown、纯文本、SVG、LaTeX 公式，打开文件，另存为，返回文稿列表，设置，关于。设置和关于各自是独立半模态。保存用 `checkmark_circle`，与系统「备忘录」编辑页标题栏一致：系统符号表没有 save，`square_and_arrow_down` 是下载符号 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`documentTitle`、`DocumentMenuContent`、`afterMenu`） |
| 选择文件打开 | 应用内用系统 `DocumentViewPicker` 取得 URI。文件管理器可通过 `viewData` / `FileOpen` 打开 `.md`、`.markdown`、`.txt`、`.svg`、`.tex`，直接进入编辑页。文件名后缀优先，否则采用系统声明的 UTD 或 MIME；两者都不匹配时拒绝打开，不按 Markdown 渲染 | [module.json5](../entry/src/main/module.json5)、[EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`openUri`） |
| 最近文稿 | 本地保留最多 12 个最近 URI。首页列表行显示文件名和格式名。再次打开时尝试激活持久化授权，授权无效时需重新选择文件 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`release`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`RecentRow`） |
| 原位置保存与另存为 | 写入授权允许时按原 URI 写回；只读授权或写入失败时改为另存为。保存后按字节指纹和正文再读校验。提供方不保证写入原子性 | [DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)（`save`）、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`write`） |
| 未保存内容保护与草稿恢复 | 切换文稿时可保存并打开、放弃修改或取消。打开失败时保留当前文稿和草稿。延迟保存**一份**应用私有草稿，可从首页恢复；原授权失效时草稿仍可另存为 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`confirmSwitch`、`scheduleRecovery`、`restoreRecovery`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 外部修改检查 | 保存前对比打开或上次成功保存时的 SHA-256 字节指纹，不一致则拒绝覆盖，可另存为 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`write`） |
| 文本编码及换行 | 读取 UTF-8、UTF-16 LE/BE、GB18030，记录 BOM 和换行并写回。写回后字符对不上则拒绝保存。混合换行仅在行数不变时原样写回；行数变化时原地保存会被拒绝，另存为改为 LF。暂无手动选择编码的界面 | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets) |
| 文件读取范围 | 文件大小超过 8 MiB 会拒绝读取；读写当前在 UI 线程同步执行 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |

## 编辑与工作区

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 源码编辑 | ArkUI `TextArea` 支持基础文本输入、光标和选区。行数、字符数和保存状态显示在文稿页标题的副标题。无多光标、语法折叠、行级语法高亮 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`EditPage`、`updateSource`、`statusLine`） |
| 快捷插入 | Markdown 的标题、强调、链接、任务、代码围栏等从编辑页工具栏插入，图标使用系统符号；放不下的项由工具栏收进更多。其他格式目前没有快捷插入 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)（`inserts`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`insertToken`、`editorTools`） |
| 查找与替换 | 精确文本匹配、下一处跳转、单处替换；没有正则或全部替换 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`FindBar`、`findNext`、`replaceMatch`） |
| Markdown 大纲 | 提取代码围栏以外的 ATX 标题，点击可跳到文本偏移；尚未解析 Setext 标题 | [Document.ets](../entry/src/main/ets/model/Document.ets)（`documentOutline`）、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets) |
| 编辑／预览／分栏 | 文稿页是 `HdsNavDestination`。`Tabs` 在编辑、预览、大纲之间切换；宽度达到 720vp 时增加编辑与预览分栏。大纲标签只对声明支持大纲的格式出现。打开文件后直接进入编辑 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`WorkspacePage`、`SplitPage`） |
| 主题设置 | 四宫格里的「设置」打开底部半模态。其中的「外观」用单选切换跟随系统、浅色、深色；本地保存偏好并同步 ArkWeb 预览。设置半模态绑定在外层容器，关于半模态绑定在 `HdsNavigation` 上：同一节点挂两个 `bindSheet` 会互相顶掉 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`changeTheme`、`SettingsPage`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[styles.css](../renderer/src/styles.css) |

## 支持的文稿格式与预览

文稿格式、默认文件名及选择器过滤由 [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) 统一定义；预览使用打包进应用的离线 ArkWeb 资源，ArkTS 以格式 ID 和正文更新预览。

| 格式 | 当前预览行为 | 实现与限制 |
| --- | --- | --- |
| `.txt` | 原样展示普通文本，保留换行与缩进，不解释 Markdown | [plain.ts](../renderer/src/renderers/plain.ts) |
| `.md`、`.markdown` | markdown-it 渲染标题、列表、表格、代码块等；支持内嵌 KaTeX 数学公式和 `svg` 代码围栏 | [markdown.ts](../renderer/src/renderers/markdown.ts)；原始 HTML 不参与解析，外部图片不加载 |
| `.svg` | DOMPurify 清理后显示静态 SVG；部分内部片段引用可用 | [svg.ts](../renderer/src/renderers/svg.ts)；脚本、动画、外部资源受限，当前安全规则仍需收紧 |
| `.tex` | KaTeX 渲染数学表达式及其支持的环境 | [tex-math.ts](../renderer/src/renderers/tex-math.ts)；不支持 `\documentclass`、宏包与完整 TeX/PDF 文档编译 |

共享预览入口位于 [renderer/src/main.ts](../renderer/src/main.ts)。页面通过 `MarknotePreview.update` 接收内容和主题，ArkUI 端将连续更新合并约 120ms，见 [Index.ets](../entry/src/main/ets/pages/Index.ets)（`schedulePreview`、`sendPreview`）。应用内选择器遇到没有后缀的文件时按纯文本打开。系统打开请求若后缀和声明类型都对不上，直接拒绝。

## 应用与分发相关的可用界面

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 应用启动与原生导航 | `EntryAbility` 为 singleton，加载 ArkUI 主页面，键盘避让跟随光标。首页是 `HdsNavigation`，文稿页是 `HdsNavDestination`。冷启动和热启动的文件请求共用 `LaunchRequests`。菜单、编辑、主题由 ArkUI 绘制，ArkWeb 只负责内容预览。不包含其他应用的分享入口 | [EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[LaunchRequests.ets](../entry/src/main/ets/document/LaunchRequests.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |
| 离线预览 | 预览 JavaScript、CSS、KaTeX 字体通过 Vite 打包在本地；当前模块没有声明网络权限，预览页通过 CSP 禁止网络连接 | [index.html](../renderer/index.html)、[vite.config.ts](../renderer/vite.config.ts)、[module.json5](../entry/src/main/module.json5) |
| 第三方许可说明 | 四宫格「关于」打开半模态，读取构建生成的许可证全文，并附带隐私说明；缺少生成资源时显示提示，尚不能据此认定可发行 HAP 已包含完整声明 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`openLegal`、`LegalPage`）、[generate-notices.mjs](../renderer/scripts/generate-notices.mjs) |

## 更新原则

- **与功能代码一起修改**：新功能真正接入用户操作路径后，补入对应行；修改、移除或改变限制时直接更新原行，删除过时描述。
- **记录用户结果及代码所有者**：以“用户能做什么、目前有什么限制、去哪里改”为核心；不为单个 helper、库依赖或未开始的任务单列功能。
- **保持文档各司其职**：本页写当前产品功能；架构与职责关系写 `ARCHITECTURE.md`；构建和许可证义务分别由 `CONTRIBUTING.md`、`STORE_RELEASE.md` 和 `third_party/README.md` 说明。未开发需求通过 GitHub Issues 等任务渠道管理。
- **新文件格式**：当格式已从文件选择、新建、编辑接通到实际预览时，同时更新 `FormatRegistry`、对应渲染器和本页；仅添加解析库或格式常量时，不登记为可用格式。
