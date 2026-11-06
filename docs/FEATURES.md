# 功能目录

本文记录用户可以使用的功能、当前限制和主要代码位置。模块职责见[架构](ARCHITECTURE.md)，构建方法见[构建与贡献](../CONTRIBUTING.md)。

## 文稿与文件

| 功能 | 当前行为与限制 | 主要代码 |
| --- | --- | --- |
| 新建与打开 | 首页可新建 Markdown、纯文本、SVG 和 LaTeX 文稿，也可通过系统选择器打开文件。文件管理器可以通过系统文件关联打开受支持的文稿，默认进入预览。格式优先按文件后缀识别，其次使用系统声明的类型 | [HomeView.ets](../entry/src/main/ets/pages/HomeView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)、[FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)、[module.json5](../entry/src/main/module.json5) |
| 最近文稿 | 本机最多保存 12 条记录，只收录已经持久化授权的文件。临时授权的文件可以查看和编辑，但不加入最近文稿。再次打开失败时可选择保留或移除记录；移除记录不会删除文件 | [LocalState.ets](../entry/src/main/ets/storage/LocalState.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |
| 保存与另存为 | 有写入授权时可保存到原 URI；原文件无法写入或保存失败时可另存为。另存成功后继续编辑新文件；授权未持久化时保存后会提示。写入前检查文件是否被外部修改，发现冲突时拒绝覆盖。保存后重新读取并校验内容；文件提供方不保证写入操作具有原子性 | [DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets)、[DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |
| 未保存内容 | 离开已修改的文稿前，应用询问是否保存。编辑时会在应用私有目录保存草稿，供异常退出后恢复；正常离开时清除草稿 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets)、[LocalState.ets](../entry/src/main/ets/storage/LocalState.ets) |
| 编码与换行 | 支持 UTF-8、UTF-16 LE/BE 和 GB18030，保存时保留原编码、BOM 和换行方式。混合换行的文件在行数改变后不能直接按原方式保存；另存为时使用 LF。当前不能手动选择编码 | [TextEncoding.ets](../entry/src/main/ets/document/TextEncoding.ets)、[DocumentService.ets](../entry/src/main/ets/document/DocumentService.ets) |
| 文件大小 | 超过 8 MiB 的文件不能打开。文件读写目前在 UI 线程同步执行 | [DocumentFiles.ets](../entry/src/main/ets/storage/DocumentFiles.ets) |

## 编辑与预览

| 功能 | 当前行为与限制 | 主要代码 |
| --- | --- | --- |
| 编辑 | 使用 ArkUI `TextArea` 编辑源文本，支持光标和选区。切换到编辑页签不会主动弹出键盘；点击文本后才进入输入状态。不支持多光标、语法折叠或行级语法高亮 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 快捷插入 | Markdown 编辑页提供标题、强调、链接、列表、待办、代码和公式等快捷操作。工具栏位于顶部标题栏下方，空间不足时可横向滚动。其他格式不显示格式工具栏 | [FormatRegistry.ets](../entry/src/main/ets/document/FormatRegistry.ets)、[FormatBarView.ets](../entry/src/main/ets/pages/FormatBarView.ets) |
| 查找与替换 | 按字面文本查找，可跳到下一处并替换单处；不支持正则表达式和全部替换 | [TextSearch.ets](../entry/src/main/ets/document/TextSearch.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 文稿大纲 | Markdown 提取代码围栏以外的 ATX 标题，暂不解析 Setext 标题；LaTeX 使用预览解析得到的章节标题和源文本位置。大纲按级别分层，可展开、折叠并跳转到编辑位置 | [Document.ets](../entry/src/main/ets/model/Document.ets)、[tex.ts](../renderer/src/renderers/tex.ts)、[DocumentOutlineView.ets](../entry/src/main/ets/pages/DocumentOutlineView.ets) |
| 撤销与重做 | 编辑历史保存在内存中，连续输入在 600 毫秒内合并，最多保留 200 步；切换文稿时清空 | [EditHistory.ets](../entry/src/main/ets/document/EditHistory.ets)、[DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets) |
| 页面与分栏 | 文稿默认打开预览，底部页签提供预览、编辑和大纲；不支持大纲的格式不显示大纲页签。宽度达到 `WIDTH_LG` 断点时增加编辑与预览分栏 | [DocumentView.ets](../entry/src/main/ets/pages/DocumentView.ets)、[Index.ets](../entry/src/main/ets/pages/Index.ets) |

预览页面随应用离线打包。ArkUI 将格式、正文、主题和修订号传给网页；LaTeX 预览通过消息端口回传解析结果，网页不能调用文件或导航接口。内容安全策略禁止网络连接。

| 格式 | 预览方式 | 限制 |
| --- | --- | --- |
| `.txt` | 显示原文，保留换行和缩进 | 不解释 Markdown |
| `.md`、`.markdown` | 使用 markdown-it 渲染，支持表格、代码围栏、KaTeX 数学公式和 SVG 代码围栏 | 不解析原始 HTML，不加载外部图片 |
| `.svg` | 使用 DOMPurify 清理后显示静态 SVG | 不执行脚本和动画，不加载外部资源；部分内部片段引用可用 |
| `.tex` | MyST 转换常见 LaTeX 文稿，KaTeX 渲染公式；无标记内容按正文显示，公式可使用数学定界符或受支持的独立公式命令 | 不执行 TeX 引擎或编译 PDF；宏包、命令和环境仅支持转换器已实现的部分，不支持的内容可能省略并提示；TikZ 尚未接入 |

预览入口是 [main.ts](../renderer/src/main.ts)，各格式的实现位于 [renderer/src/renderers](../renderer/src/renderers/)。

## 设置与导航

设置从首页或文稿页的更多菜单进入。外观提供跟随系统、浅色和深色三个选项，偏好保存在本机；设置页还提供隐私说明、开源许可证和关于。

“开源许可证”页分别提供本项目和第三方许可证全文。“关于”页显示应用名称、版本及 GitHub 项目主页入口；主页交给系统浏览器打开。

标题栏使用 HDS 导航组件，菜单使用系统菜单组件。文稿标题栏显示文件名，不显示行数、字符数或保存状态。对不支持沉浸材质或处于 `SMOOTH` 材质档位的设备，菜单关闭沉浸材质并使用系统默认背板。

主要代码：[SettingsView.ets](../entry/src/main/ets/pages/SettingsView.ets)、[SettingsDetail.ets](../entry/src/main/ets/pages/SettingsDetail.ets)、[SettingsPage.ets](../entry/src/main/ets/pages/SettingsPage.ets)、[MenuMaterialOptions.ets](../entry/src/main/ets/pages/MenuMaterialOptions.ets)。

## 公共滚动行为

首页和设置页使用原生 `List`；文稿页签和分栏使用 `DocumentScrollLayer` 中的 `Scroll`。这些页面通过 `PageScrollPolicy` 共用边缘回弹、按需显示滚动条及安全区配置，同时各自持有滚动控制器。

标题栏使用 `HdsMaterialStyles` 中的公共配置。初始内容避开标题栏的模糊区域；向上滚动时，内容可以进入标题栏下方并显示模糊效果。预览使用 ArkWeb 的 `FIT_CONTENT`，页面滚动由外层滚动容器处理。

主要代码：[PageScrollPolicy.ets](../entry/src/main/ets/pages/PageScrollPolicy.ets)、[HdsMaterialStyles.ets](../entry/src/main/ets/pages/HdsMaterialStyles.ets)、[DocumentScrollLayer.ets](../entry/src/main/ets/pages/DocumentScrollLayer.ets)。
