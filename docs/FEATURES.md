# Marknote 功能目录

本目录供开发者查找**当前源码已接入的用户功能**及其负责位置。条目描述能够经现有应用入口触达的行为，并在同一处说明实际限制；不把功能设想、待办事项或发行进度登记为已实现功能。

这里记录的是**源码实现范围**，不附加真机验收或应用市场审核结论。实现原理与模块依赖见 [ARCHITECTURE.md](ARCHITECTURE.md)，构建及验证方式见 [CONTRIBUTING.md](../CONTRIBUTING.md)，发行事项见 [STORE_RELEASE.md](STORE_RELEASE.md)。

## 文稿与文件

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 首页与文稿创建 | 首页可新建 Markdown、纯文本、SVG、TeX 数学公式文稿；默认名称与初始内容按格式确定 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`LibraryPage`、`startNew`）、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) |
| 选择文件打开 | 从应用内调用系统 `DocumentViewPicker` 获取 URI，按文件名识别格式；**尚未注册系统「打开方式」入口** | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`chooseOpen`、`read`）、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) |
| 最近文稿 | 本地保留最多 12 个最近 URI；再次打开时尝试激活持久化授权，授权无效时需重新选择文件 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`prepare`、`release`） |
| 原位置保存与另存为 | 基于文件 URI 写入；另存为通过系统选择器取得目标 URI；保存后重新读取校验。提供方不保证写入原子性 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`saveFile`）、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`write`） |
| 未保存内容保护与草稿恢复 | 切换文稿前提示未保存修改；延迟保存**一份**应用私有草稿，可从首页恢复。当前恢复过程仍依赖原 URI 授权 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`guardChanges`、`scheduleRecovery`、`restoreRecovery`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 外部修改检查 | 保存前对比打开时的文本及编码/换行元数据，发现差异会拒绝覆盖；**尚未校验原始字节指纹** | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)（`write`） |
| 文本编码及换行 | 读取 UTF-8、UTF-16 LE/BE、GB18030，记录 BOM 和换行信息并尝试写回；编码自动识别、独立 CR 换行等仍有无损性缺陷，暂无手动选择编码 UI | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets) |
| 文件读取范围 | 文件大小超过 8 MiB 会拒绝读取；读写当前在 UI 线程同步执行 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |

## 编辑与工作区

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 源码编辑 | ArkUI `TextArea` 支持基础文本输入、光标和选区；无多光标、语法折叠、行级语法高亮 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`EditPage`、`updateSource`） |
| 快捷插入 | Markdown 提供标题、强调、链接、任务、代码围栏等快捷输入；其他格式目前没有专用快捷键 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)（`inserts`）、[Index.ets](../entry/src/main/ets/pages/Index.ets)（`insertToken`） |
| 查找与替换 | 精确文本匹配、下一处跳转、单处替换；没有正则或全部替换 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`FindBar`、`findNext`、`replaceMatch`） |
| Markdown 大纲 | 提取代码围栏以外的 ATX 标题，点击可跳到文本偏移；尚未解析 Setext 标题 | [Document.ets](../entry/src/main/ets/model/Document.ets)（`documentOutline`）、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets) |
| 编辑／预览／分栏 | 原生 Tabs 切换内容；宽度达到 720 时提供编辑与预览分栏；大纲标签只对声明支持大纲的格式出现 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`WorkspacePage`、`SplitPage`） |
| 主题设置 | 跟随系统、浅色、深色；本地保存偏好并同步 ArkWeb 预览 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`changeTheme`）、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[styles.css](../renderer/src/styles.css) |

## 支持的文稿格式与预览

文稿格式、默认文件名及选择器过滤由 [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets) 统一定义；预览使用打包进应用的离线 ArkWeb 资源，ArkTS 以格式 ID 和正文更新预览。

| 格式 | 当前预览行为 | 实现与限制 |
| --- | --- | --- |
| `.txt` | 原样展示普通文本，保留换行与缩进，不解释 Markdown | [plain.ts](../renderer/src/renderers/plain.ts) |
| `.md`、`.markdown` | markdown-it 渲染标题、列表、表格、代码块等；支持内嵌 KaTeX 数学公式和 `svg` 代码围栏 | [markdown.ts](../renderer/src/renderers/markdown.ts)；原始 HTML 不参与解析，外部图片不加载 |
| `.svg` | DOMPurify 清理后显示静态 SVG；部分内部片段引用可用 | [svg.ts](../renderer/src/renderers/svg.ts)；脚本、动画、外部资源受限，当前安全规则仍需收紧 |
| `.tex` | KaTeX 渲染数学表达式及其支持的环境 | [tex-math.ts](../renderer/src/renderers/tex-math.ts)；不支持 `\documentclass`、宏包与完整 TeX/PDF 文档编译 |

共享预览入口位于 [renderer/src/main.ts](../renderer/src/main.ts)。页面通过 `MarknotePreview.update` 接收内容和主题，ArkUI 端将连续更新合并约 120ms，见 [Index.ets](../entry/src/main/ets/pages/Index.ets)（`schedulePreview`、`sendPreview`）。源格式未知时，格式注册表回退为纯文本；这不表示具备该格式的专用解析功能。

## 应用与分发相关的可用界面

| 功能 | 当前行为与边界 | 负责代码 |
| --- | --- | --- |
| 应用启动与原生导航 | `EntryAbility` 加载 ArkUI 主页面；界面、菜单、编辑、主题等由 ArkUI 绘制，ArkWeb 仅负责内容预览 | [EntryAbility.ets](../entry/src/main/ets/entryability/EntryAbility.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |
| 离线预览 | 预览 JavaScript、CSS、KaTeX 字体通过 Vite 打包在本地；当前模块没有声明网络权限，预览页通过 CSP 禁止网络连接 | [index.html](../renderer/index.html)、[vite.config.ts](../renderer/vite.config.ts)、[module.json5](../entry/src/main/module.json5) |
| 第三方许可说明 | 应用内页面尝试读取构建生成的许可证全文；缺少生成资源时显示提示，尚不能据此认定可发行 HAP 已包含完整声明 | [Index.ets](../entry/src/main/ets/pages/Index.ets)（`openLegal`、`LegalPage`）、[generate-notices.mjs](../renderer/scripts/generate-notices.mjs) |

## 更新原则

- **与功能代码一起修改**：新功能真正接入用户操作路径后，补入对应行；修改、移除或改变限制时直接更新原行，删除过时描述。
- **记录用户结果及代码所有者**：以“用户能做什么、目前有什么限制、去哪里改”为核心；不为单个 helper、库依赖或未开始的任务单列功能。
- **保持文档各司其职**：本页写当前产品功能；架构与职责关系写 `ARCHITECTURE.md`；构建和许可证义务分别由 `CONTRIBUTING.md`、`STORE_RELEASE.md` 和 `third_party/README.md` 说明。未开发需求通过 GitHub Issues 等任务渠道管理。
- **新文件格式**：当格式已从文件选择、新建、编辑接通到实际预览时，同时更新 `FormatRegistry`、对应渲染器和本页；仅添加解析库或格式常量时，不登记为可用格式。
