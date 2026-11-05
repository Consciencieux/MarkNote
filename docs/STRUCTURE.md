# 仓库结构

本文介绍目录用途和常见改动的位置。模块如何协作见[架构](ARCHITECTURE.md)。

```text
marknote/
├── AppScope/                         应用包名、版本、名称和图标
├── entry/                            HarmonyOS 应用模块
│   └── src/main/
│       ├── module.json5              Ability、文件关联和权限
│       ├── ets/
│       │   ├── entryability/         应用启动及系统文件打开入口
│       │   ├── pages/                首页、文稿、设置及公共界面组件
│       │   ├── document/             文稿会话、格式、编辑历史、查找和编码
│       │   ├── model/                文稿及大纲数据结构
│       │   └── storage/              文件访问和本机状态
│       └── resources/rawfile/        构建生成的预览页与许可证文本
├── renderer/                         离线预览源码及构建脚本
│   ├── src/renderers/                各文稿格式的渲染器
│   ├── src/styles.css                预览样式
│   └── scripts/                      打包资源及生成许可证声明
├── docs/                             功能、架构、隐私及发布文档
├── examples/                         Markdown、SVG 和 TeX 示例文稿
├── third_party/                      第三方依赖说明
├── README.md                         产品概览
├── CONTRIBUTING.md                   构建与验证
├── AGENTS.md                         项目开发约定
├── build-profile.example.json5       构建配置模板
├── hvigorfile.ts                     应用构建入口
└── oh-package.json5                  OHPM 工程描述
```

## 常见改动

除特别注明的路径外，下表中的路径相对于 `entry/src/main/ets/`。

| 修改内容 | 主要位置 |
| --- | --- |
| 首页列表和新建菜单 | `pages/HomeView.ets`、`pages/Index.ets` |
| 文稿编辑、查找和保存 | `pages/DocumentView.ets` |
| 文稿预览和大纲界面 | `pages/DocumentPreviewView.ets`、`pages/DocumentOutlineView.ets` |
| 编辑工具栏 | `pages/FormatBarView.ets`、`document/FormatRegistry.ets` |
| 标题栏与滚动 | `pages/HdsMaterialStyles.ets`、`pages/PageScrollPolicy.ets`、`pages/DocumentScrollLayer.ets` |
| 设置页面 | `pages/SettingsPage.ets`、`pages/SettingsView.ets`、`pages/SettingsDetail.ets`、`pages/SettingsListRow.ets` |
| 菜单及跨页面操作 | `pages/DocumentMenus.ets`、`pages/DocumentBridge.ets`、`pages/MenuMaterialOptions.ets` |
| 文稿打开、保存和草稿恢复 | `document/DocumentService.ets`、`storage/DocumentFiles.ets`、`storage/LocalState.ets` |
| 文件编码与换行 | `document/TextEncoding.ets` |
| 格式注册与文件关联 | `document/FormatRegistry.ets`，仓库根目录下的 `entry/src/main/module.json5` 和 `renderer/src/renderers/` |
| 预览行为与样式 | 仓库根目录下的 `renderer/src/main.ts`、`renderer/src/renderers/` 和 `renderer/src/styles.css` |

`entry/src/main/resources/rawfile/preview/index.html` 和 `rawfile/licenses/` 中的许可证文件由预览构建生成；修改预览或依赖后，按[构建与贡献](../CONTRIBUTING.md)中的步骤重新生成。

本机 `build-profile.json5`、签名材料、构建产物、缓存和安装的依赖不提交到版本库。
