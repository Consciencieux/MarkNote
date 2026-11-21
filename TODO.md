# 待办

## 本地图片预览

- [ ] **SVG 误拒绝（N04）**：按 XML 结构检查本地 SVG。说明文字里的网址和 Inkscape 命名空间应能正常显示，脚本和外部资源仍受限制。复用现有清理器前，核对其移除动画的规则对本地图片的影响。[本地图片](entry/src/main/ets/document/LocalImages.ets)、[SVG 清理](renderer/src/renderers/svg.ts)
- [ ] **动态图缩放（N03）**：目前需要缩小的 GIF 和动态 WebP 只显示首帧。评估用 Image Kit 识别多帧，在窄栏和分栏保留播放时序的方法；核对大动图的解码内存，保留静态图按显示尺寸解码的行为。[缩图实现](entry/src/main/ets/document/LocalImages.ets)
- [ ] **图片传输（N01）**：验证 ArkWeb 能否用文件描述符返回原图和缩略图，替代逐块确认和网页端拼装 Blob。核对可见范围加载、文稿授权、内容安全策略、换篇取消和句柄释放，再决定是否替换。[原生传输](entry/src/main/ets/pages/DocumentPreviewView.ets)、[网页接收](renderer/src/image-window.ts)

## 首页文稿操作

- [ ] **长按菜单**：将 `feature/home-document-actions` 已实现的分享、另存副本、多选、收藏／取消收藏、移除记录和删除文件合入 `dev`。在“全部”和“收藏”中核对操作对象。分享读取所选文件已保存的内容，另存副本保留原件，移除记录保留文件，确认删除才移入回收站。
- [ ] **多选与批量操作**：合入时核对选择和退出多选、批量分享、收藏、移除记录与删除。另存副本仅用于单篇文稿。检查批量操作中一项失败后，其余项的处理结果及列表状态。

## 文稿功能

- [ ] **混合换行保存**：混合 LF、CRLF、CR 的文稿增删行后，当前不能按原方式保存；另存为使用 LF。明确新增和删除行的换行策略及用户选择，避免静默改变原文件。[编码与换行](entry/src/main/ets/document/TextEncoding.ets)
- [ ] **无 BOM 编码识别**：UTF-16 依赖前 64 字节的零字节比例判断，当前不能手动纠正编码。完善识别和用户纠正途径，保留现有 BOM 与编码安全处理。[编码识别](entry/src/main/ets/document/TextEncoding.ets)
- [ ] **界面文字方向（N08）**：用 Localization Kit 的 `i18n.isRTL` 按实际生效的界面语言统一原生和预览的方向判断。核对跟随系统和手动选择阿拉伯语、维吾尔语时的表现，保留编辑器正文当前的自动方向行为。[应用语言](entry/src/main/ets/i18n/AppLanguage.ets)、[预览](renderer/src/main.ts)

## 界面适配待确认

- [ ] **编辑器滚动条（N02）**：核对 ArkWeb 原生滚动条能否在编辑和分栏中将滑块限制在上下悬浮栏之间，同时允许正文滚入渐变区。验证触控和鼠标拖动、行末文字与两栏轨道范围，再决定是否移除自绘滚动条。[编辑器宿主](entry/src/main/ets/pages/DocumentCodeEditor.ets)、[滚动条](editor/src/source-scrollbar.ts)
- [ ] **底部避让**：在无系统导航指示区的窗口核对额外底边距、末行和悬浮页签的点击区域。[文稿页面](entry/src/main/ets/pages/DocumentView.ets)、[滚动层](entry/src/main/ets/pages/DocumentScrollLayer.ets)
- [ ] **窄窗口查找栏**：已在三折叠收拢的窄屏确认首次展开、匹配计数和替换行均可见。保留搜索框内的计数和上下箭头，核对窄屏叠加系统大字体时清除按钮、结果导航和正文顶部是否遮挡。[查找栏](entry/src/main/ets/pages/DocumentFindBar.ets)
- [ ] **首页分段按钮**：窄侧栏、大字体和长译文组合下检查“全部／收藏”是否完整可读且可点击。当前两侧有 40vp 占位，中间最大宽度为 150vp。[首页](entry/src/main/ets/pages/Index.ets)
- [ ] **设置行和分组标题**：核对 ComposeListItem 能否在 CARD 内承载标题、右侧状态和箭头。单选行需保留整行点击，并核对选中状态的朗读。“主题”位于代码高亮二级页的选项卡片上方，标题与选项各用一个列表组。保留这个位置，核对分组语义、对齐及无障碍朗读。[设置行](entry/src/main/ets/pages/SettingsListRow.ets)、[设置详情](entry/src/main/ets/pages/SettingsDetail.ets)
- [ ] **图标与底部距离的资源用途**：部分符号尺寸使用 `Title_M`，无导航指示区时底部距离使用 `margin_left`。核对组件适用资源及实际显示，底部遮挡与上述避让事项一并处理。[文字与图标样式](entry/src/main/ets/pages/TextRoles.ets)
- [ ] **阅读与 Web 视觉配置**：编辑、预览与大纲已共用系统横向边距，帮助等页面使用应用选定的栅格与 24vp 侧距。核对编辑、预览及其他阅读页面的基础字号、颜色和版心，保留文稿排版与灰色代码框。[阅读版心](entry/src/main/ets/pages/SettingsReadingFrame.ets)、[预览样式](renderer/src/styles.css)、[编辑器样式](editor/src/production.css)
- [ ] **大纲行结构**：保留长大纲按需创建条目。核对 TreeView 能否分别处理箭头展开和标题跳转，并支持无障碍朗读，再决定是否替换现有行和缩进。[大纲](entry/src/main/ets/pages/DocumentOutlineView.ets)
- [ ] **菜单宽度**：首页顶层菜单对所有窗口固定 224vp，其他菜单使用组件默认宽度。检查手机、大字体、平板和小窗口下的内容显示，并核对适用的官方设计范围。[菜单](entry/src/main/ets/pages/DocumentMenus.ets)

以上界面项包含需要确认的应用自定义选择，是否修改以官方组件适用性和实际交互结果为准。

## 已开始但尚未完成验证

- [ ] **持久授权 F06**：持久授权申请已延后到打开确认后，接管失败时尝试释放新增授权，已有读授权时只释放新增的写授权。验证取消、读取失败、授权升级和会话切换。
- [ ] **分享缓存 F08**：后续分享时会清理超过七天的副本，分享准备或面板打开失败时尝试清理本次副本。验证接收方读取与清理失败重试。
- [ ] **保存与恢复故障场景**：已修复保存和草稿恢复的主要问题；在模拟器或设备上核对文件提供方写入失败、外部修改冲突、恢复读取失败和清理失败时的结果。
- [ ] **输入与国际化**：中文候选上屏及保存已有模拟器记录；补查日文输入法、RTL 和中英文混排下的输入、选区与定位。
