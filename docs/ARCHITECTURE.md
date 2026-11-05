# 架构

界面由 ArkUI 实现。文稿的格式判断、编码处理和文件读写集中在独立模块，页面只负责呈现和调度。各模块的具体行为边界见[功能目录](FEATURES.md)。

## 模块职责

| 模块 | 职责 |
| --- | --- |
| `EntryAbility` | 以 singleton 启动。桌面启动进入首页，`ohos.want.action.viewData` 的文件请求交给 `LaunchRequests`。页面尚未创建时先保留这次请求，页面就绪后再打开，避免冷启动丢失文件。 |
| `DocumentService` | 当前文稿的会话状态，包括身份、正文、格式、来源和修订状态。新建、系统选择器、最近文稿和系统打开都从这里进入；保存、另存为、草稿恢复和外部冲突判断也在此决定。 |
| `FormatRegistry` | 扩展名、UTD、MIME、默认文件名、大纲支持和快捷插入。文件名能匹配已注册后缀时以文件名为准，否则使用系统声明的类型。无法识别的系统类型不会被当成 Markdown。 |
| `TextEncoding` | 把字节还原成编辑器使用的 `\n` 文本，保存时写回原编码、BOM 和换行，支持 UTF-8、UTF-16 LE/BE 和 GB18030。写回后字符对不上时拒绝写入。 |
| `DocumentFiles` | 文件选择、读取、写入授权判断、持久授权、冲突检测和写回。冲突检测比对打开时或上次保存成功时的 SHA-256 字节指纹。只有读取授权时，保存改为另存为。 |
| `LocalState` | 最近文稿列表、未保存草稿和外观偏好的本机存储。 |

## 界面

首页是 `HdsNavigation`，文稿页是 `HdsNavDestination`。首页列表滚到标题栏下方，标题栏材质跟随系统；文稿页内容在标题栏下方截断，所以关闭标题栏模糊、用不透明背板。新建和打开入口留在首页内容区，保存、查找和更多入口位于文稿页标题栏。编辑、预览、大纲和分栏由 `Tabs` 切换，宽度达到 720vp 时出现分栏。键盘避让使用 `RESIZE_WITH_CARET`，页面内的工具栏和页签栏都不随键盘重新定位。

标题栏的四宫格菜单用 `Menu`、`MenuItemGroup` 和 `MenuItem` 实现，通过 `promptAction.openMenu` 锚定到标题栏图标，菜单项用通用的 `.onClick()` 触发动作。一级菜单只放当前页面能执行的动作，不放「关于」这类说明性入口。

设置是全屏页面，推在首页同一个 `NavPathStack` 上：导航页和内容页都用 `HdsNavDestinationTitleMode.MINI`，并开 `enableComponentSafeArea` 让内容避让标题栏，返回键由导航组件提供。设置不走半模态——`bindSheet` 的文档把它的场景限定为「简单的任务或信息面板」，带二级页的设置属于导航层级，两者混用会出现从底部弹起却占满整屏的形态。

带 `ListItemGroupStyle.CARD` 的页面必须自己给页面底色（`sys.color.ohos_id_color_sub_background`），卡片是有抬升的一层，页面底不设色就会贴在窗口底上，浅色模式下卡片和页面同色。结构照官方《如何设置分组列表的圆角和间距》：外层容器给底色，卡片保持组件默认。

## 预览

预览资源由 `renderer/` 构建后放入 HAP。`renderer/src/renderers/` 按格式 ID 分为 `plain`、`markdown`、`svg` 和 `tex-math`，页面只把格式 ID 和正文交给预览，连续编辑产生的更新合并为约 120ms 一次。

预览与 ArkUI 之间只有单向的 `MarknotePreview.update` 调用。预览页不注册 ArkTS 接口，也不具备联网能力。

## 系统文件关联

文件关联注册在 `module.json5`：`file` scheme 搭配 `FileOpen`，类型为 `general.markdown`、`general.plain-text`、`general.svg-image`、`org.tug.tex` 和 `general.tex`。SDK 中的 TeX 统一类型是 `general.tex`，因此一并注册，避免文件管理器匹配不到。不注册 `general.file` 和 `general.text`。
