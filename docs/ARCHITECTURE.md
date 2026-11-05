# 架构

MarkNote 使用 ArkUI 实现应用界面和文稿操作，使用 ArkWeb 展示离线预览。功能行为与限制见[功能目录](FEATURES.md)，文件位置见[仓库结构](STRUCTURE.md)。

## 文稿数据流

`EntryAbility` 接收桌面启动和系统文件打开请求。文件请求经 `LaunchRequests` 交给页面；页面尚未就绪时，请求会暂存。

`DocumentService` 管理当前文稿会话，并协调新建、打开、保存和草稿恢复。相关模块的职责如下：

| 模块 | 职责 |
| --- | --- |
| `FormatRegistry` | 定义文件扩展名、系统类型、默认文件名、大纲支持和编辑快捷操作。 |
| `DocumentFiles` | 调用系统文件选择器，处理 URI 授权、文件读取、写入和外部修改检查。 |
| `TextEncoding` | 在文件字节和编辑器文本之间转换，记录并恢复编码、BOM 与换行方式。 |
| `LocalState` | 保存最近文稿、草稿和外观偏好。 |
| `EditHistory`、`TextSearch` | 分别处理编辑历史和字面文本查找。 |

文件格式优先按已知后缀识别，其次按系统声明的类型识别。保存前的外部修改检查使用文件字节的 SHA-256 指纹。

## 界面与导航

首页使用 `HdsNavigation`。文稿和设置页面使用 `HdsNavDestination`，并由同一个 `NavPathStack` 管理。`Index` 创建设置页路由，`SettingsPage` 构建各级页面；每个页面持有自己的滚动控制器。

`HdsMaterialStyles` 配置公共标题栏，`PageScrollPolicy` 配置原生滚动容器的公共行为。文稿预览、编辑、大纲和分栏使用 `DocumentScrollLayer`，各自保留滚动控制器。文稿页通过 `HdsTabs` 切换视图，格式快捷操作位于导航标题栏的底部自定义区域。

`DocumentView` 持有文稿编辑和保存状态，并协调页签；`DocumentPreviewView` 管理各自的 Web 控制器和预览更新，`DocumentOutlineView` 管理大纲展示与展开状态。

首页和文稿页的标题栏菜单使用系统菜单组件；`DocumentMenus` 和 `DocumentBridge` 负责跨页面的菜单动作与离开确认。

## 离线预览

`renderer/` 将预览页面、依赖和字体打包为单个 HTML 文件。ArkUI 通过 `MarknotePreview.update` 向页面传入格式、正文和主题；网页不调用 ArkTS 接口。预览资源和网络限制见[功能目录](FEATURES.md)。

## 文件关联

`entry/src/main/module.json5` 中的 `FileOpen` 将受支持的 Markdown、纯文本、SVG 和 TeX 类型交给现有 `EntryAbility`。格式识别和文件读写分别由 `FormatRegistry` 和 `DocumentFiles` 处理。
