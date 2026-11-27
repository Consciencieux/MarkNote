# 架构

MarkNote 使用 ArkUI 实现应用界面和文稿操作，使用独立的 ArkWeb 页面提供源码编辑和离线预览。功能行为与限制见[功能目录](FEATURES.md)，文件位置见[仓库结构](STRUCTURE.md)。

## 文稿数据流

`EntryAbility` 接收桌面启动和系统文件打开请求。文件请求经 `LaunchRequests` 交给页面；页面尚未就绪时，请求会暂存。冷启动先恢复异常退出留下的草稿，再按队列处理打开请求。草稿仍有未保存修改时，先按离开文稿的规则确认，再打开外部文件。

`DocumentService` 持有当前文稿会话。`Index` 串行处理打开请求，读完文件后若当前正文已变，会再次确认离开，再采用新会话。离开确认只对发起时的会话和修订有效。新建或换篇前须先清理当前会话的恢复副本。

| 模块 | 职责 |
| --- | --- |
| `FormatRegistry` | 定义文件扩展名、系统类型、默认文件名、大纲支持和编辑快捷操作。 |
| `DocumentFiles` | 调用系统文件选择器，管理 URI 授权、异步读写和文件校验。打开时先激活已有授权，读取并确认换篇后才请求持久授权。未接管文稿时，按本次记录的新增权限尝试撤销。`DocumentStream` 逐块解码及计算 SHA-256，`FileBytes.writeAll` 处理短写。 |
| `DocumentShare` | 将当前编辑内容异步写入临时分享文件，并调用系统分享面板。准备或打开面板失败时尝试清理本次副本，成功后为接收方保留文件。 |
| `DraftCoordinator` | 串行安排同一份草稿的写入、强制检查点和清理。自动草稿同时只保留一笔在途和一笔最新快照；写入失败会短暂重试。之后若有新编辑、清理或换篇，这次失败的快照不再重试。停笔 450 ms 提交，最长等待 2 s 后提交调度；落盘完成时间取决于存储。 |
| `StartupRecovery` | 在首次恢复成功前协调读取和重试，阻止新会话覆盖尚未处理的恢复副本。 |
| `DocumentAnalysis` | 正文变化立即进入会话。Markdown 大纲和查找计数按需合并，过期的会话或修订不采用。 |
| `TextEncoding` | 在文件字节和编辑器文本之间转换，记录并恢复编码、BOM 与换行方式。 |
| `LocalState` | 保存最近文稿、收藏和设置偏好。`Index` 将最近记录与收藏的更新串行提交，单项失败后队列仍可继续。`LocalState` 管理恢复副本的原子替换、读取和隔离。`DraftFile` 分块写入和读回正文，兼容旧版 JSON 恢复副本。 |
| `TextSearch` | 处理字面文本查找；撤销和重做由 CodeMirror 管理。 |
| `editor-actions` | 编辑器快捷操作直接生成局部事务，处理行前缀、选区包裹和代码围栏。 |

## 界面与导航

首页使用 `HdsNavigation`。文稿和设置页面使用 `HdsNavDestination`，并由同一个 `NavPathStack` 管理。`Index` 创建设置页路由，`SettingsPage` 构建各级页面；每个页面持有自己的滚动控制器。许可证页进入后再读取原文，并按段放进列表。`EntryAbility` 在加载页面前按已保存的语言偏好设置应用语言。跟随系统时解析为当前系统语言对应的资源，因此切换立即生效；下次冷启动会按当时的系统语言重新解析。

`HdsMaterialStyles` 配置滚动标题栏。首页和各级设置页通过 `bindToScrollable` 绑定本页列表，文稿页绑定当前页签的控制器，分栏时同时绑定预览和编辑两侧。首页、设置和大纲通过 `PageScrollPolicy` 共用边缘回弹、安全区裁切与滚动条避让设置。

预览和编辑共用 `DocumentScrollLayer`。每栏的原生 `Scroll` 管理滚动范围、系统滑块及两端回弹。ArkWeb 使用固定视口，加载完成后关闭手势滚动，连续滚动由原生层通过 `scrollBy` 派发每帧增量。布局更新和跳转使用 `scrollTo` 同步位置。预览重排时，浏览器为保持阅读位置给出的偏移与新范围一同回传，原生层只在位置未被用户移动时采用。CodeMirror 在测量阶段计算光标和查找目标的位置，经消息端口交给对应栏的 `Scroller`。大纲使用有界 `List`、`Repeat.virtualScroll` 和原生滚动条。[ArkWeb 嵌套滚动](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-nested-scrolling/) · [获取网页内容高度](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-getpage-height)

`ContainerReader` 读取文稿区域的宽度断点，从系统大宽度档起显示分栏页签。预览和编辑位于悬浮页签下方的同一个 `Row`，正文可延伸到标题栏和底部页签的渐变区。单栏由当前可见的一侧填满文稿区域，分栏由同两个 Web 实例平分分隔线以外的空间。[华为容器断点指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-layout-development-container-reader/)

`DocumentView` 持有文稿编辑、查找和保存界面状态，并按页签是否可见决定预览工作方式；查找栏 `DocumentFindBar` 只绘制查询和替换控件。保存和删除后的文稿数据由 `DocumentService` 更新。`DocumentPreviewView` 持有预览 Web 控制器，`PreviewDispatch` 保留至多一笔在途发送和一笔最新请求。`DocumentOutlineView` 管理大纲展示与展开状态。

首页和文稿页的标题栏菜单使用系统菜单组件；`DocumentMenus` 和 `DocumentBridge` 负责跨页面的菜单动作与离开确认。

## 离线预览

`renderer/` 将预览页面、依赖和字体打包为单个 HTML 文件。ArkUI 通过 `MarknotePreview.update` 向页面传入格式、正文、主题、修订号、工作模式，以及当前界面语言的预览提示。工作模式为关闭时不发送；LaTeX 大纲模式只解析并回传标题，不生成页面。隐藏的预览释放页面节点并停止着色，保留正文高度以维持页内滚动位置。Markdown 各段经 DOMPurify 清理后参与网页排版，原生滚动范围取自实际布局。浏览器的 `IntersectionObserver` 按阅读位置触发本地图片读取、代码着色和 Mermaid 绘图。文内公式定义了跨公式复用的全局宏时，整篇按源码顺序排版，以保留定义和重定义的语义。

Markdown 的图片链接和 MyST 转换的 LaTeX `\includegraphics` 都生成图片占位。共用的 `PreviewImages` 按阅读位置发出请求，应用根据当前文稿的 URI 和已有授权逐张读取。ArkWeb 提供栏宽、视口高度和像素密度，原生用 Image Kit 读取图像格式和尺寸。需要缩小的静态位图通过 ImagePacker 编码到私有临时文件，多帧 GIF 和 WebP 保留原图。ArkWeb 只为当前阅读范围内的图片分配临时地址。应用在 onInterceptRequest 中核对文稿和图片身份，用 WebResourceResponse 交付文件描述符，交付后由 ArkWeb 关闭。文稿 URI、路径校验和文件授权由原生侧处理，本地 SVG 仅在隔离的图片上下文显示。网页不注册文件或导航接口，也不加载网络图片。

Markdown 的 mermaid 代码围栏在页面清理之后画成 SVG。用户 SVG 和 Mermaid 的清理结果以 SVG 图片上下文显示，隔离样式与片段 ID；KaTeX 自身的布局 SVG 不走这一转换。LaTeX 使用 MyST 解析文稿并转换为 HTML，KaTeX 渲染公式；网页通过已有的 `WebMessagePort` 回传同一次解析得到的标题、位置、诊断和修订号。ArkUI 校验修订号与位置后显示原生大纲。Markdown 预览中的 http、https 链接不带可导航的 `href`；用户点击后，网页经同一端口发送 `open-link`，ArkTS 再校验协议、主机、凭据以及当前文稿和修订，然后调用 `openLink` 交给系统打开。预览页面不导航、不加载这些地址。

MyST 解析 `.tex` 时保留 `tikzpicture` 的源码位置。仅当起止偏移均为整数且在源码内界定非空区间时，才生成图形占位。阅读位置附近的图块由单个离线 Worker 顺序处理，使用 TikZ Editor Core 的解析、绘图和 SVG 输出模块。返回的 SVG 经清理后在隔离的图片上下文中显示。更新或隐藏预览时结束旧任务，绘制超时后重新启动 Worker 处理后续图块，大纲模式只解析标题。[功能与限制](FEATURES.md#latex-预览)

Markdown 代码围栏先显示转义后的原文，再由离线打包的 Worker 顺序运行 highlight.js；更新文稿会终止旧 Worker。着色结果仅允许 `span` 和 `class`，经 DOMPurify 清理后写回对应代码节点。Worker 不可用或解析失败时保留原文。预览和编辑器共用 `shared/code-languages.ts` 的语言别名以及 `shared/syntax-colors.ts` 的前景色，具体语言引擎各自配置。

## 源码编辑器

`editor/` 将 CodeMirror 6 和语言支持打包为独立离线编辑器。`DocumentCodeEditor` 通过受控消息端口连接 `DocumentView`，不向网页暴露文件、导航或通用 ArkTS 接口。普通编辑和宽屏分栏复用同一实例，CodeMirror 管理正文、选区和撤销历史；文件操作仍由 `DocumentService` 负责。桥接层通过会话 ID、代次、操作序号和 UTF-16 偏移传递增量，先校验当前会话和原正文、写入文稿服务，再确认并推进桥接修订。桥接修订独立于文稿服务用于分析的修订；正文更新经 `DocumentService.edit` 推进后者。保存屏障等待输入法组合结束，并确认当时已产生的变更；同步超时会取消等待并尝试重新连接，未确认编辑仍保留在编辑器中。切换或离开前暂停编辑，取消切换后恢复。冲突时保留编辑器本地正文，校验原生会话未被其他操作修改后，用完整快照和新代次恢复。

## 大文稿的读写和恢复

打开文稿时按块读取文件，解码过程中保留跨块字符与换行状态。混合换行文稿在 CodeMirror 事务中同步更新逐行换行标记，撤销记录包含对应的逆向变更。正文与换行标记一起进入保存快照和草稿。保存时先把选定快照编码到私有临时文件，再用打开文稿的解码规则对照正文。校验通过后建立恢复检查点。覆盖原文件前核对其 SHA-256 指纹，再用 Core File Kit 的 copyFile 从临时文件描述符覆盖目标，刷新后读回并校验摘要。

写后校验成功，先将确认的目标 URI、指纹和保存基线写入恢复副本，再清理副本。更新副本失败时安排重试。保存期间若产生新编辑，继续保留草稿。撤销时，只有正文与换行标记都回到保存基线且没有未确认写入，才清理草稿。

应用私有草稿使用 Core File Kit 的 AtomicFile 提交或回滚写入。新记录采用 JSON Lines，按块序列化正文、保存基线、未确认写入和混合换行标记。内容相同的字段共用同一份数据；读取时校验字段长度和引用，并兼容旧版单个 JSON 对象。读取失败时保留原件，隔离损坏副本失败时阻止新会话覆盖它。若另存目标的写入仍未确认，恢复时核对该目标的正文，无法确认则禁止直接覆盖旧 URI。原文件删除后若草稿清理失败，保留会话并解除与已删除 URI 的关联。

## 文件关联

`entry/src/main/module.json5` 中的 `FileOpen` 将受支持的 Markdown、纯文本、SVG 和 TeX 类型交给现有 `EntryAbility`。格式识别和文件读写分别由 `FormatRegistry` 和 `DocumentFiles` 处理。
