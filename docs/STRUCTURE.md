# 仓库结构

本页只说明文件和目录的用途。模块之间如何配合见 [ARCHITECTURE.md](ARCHITECTURE.md)。

```text
marknote
├── AppScope/app.json5                      包名、版本与应用图标
├── entry/src/main/
│   ├── module.json5                        Ability、FileOpen 关联与权限
│   ├── ets/
│   │   ├── entryability/EntryAbility.ets   启动与系统打开文件
│   │   ├── pages/Index.ets                 首页、编辑、预览调度、查找、菜单、主题
│   │   ├── document/
│   │   │   ├── DocumentService.ets         文稿会话、打开、保存、冲突
│   │   │   ├── FormatRegistry.ets          扩展名、UTD、MIME、大纲、快捷插入
│   │   │   ├── LaunchRequests.ets          冷启动时暂存外部文件请求
│   │   │   └── TextEncoding.ets            编码、BOM、换行
│   │   ├── model/Document.ets              文稿字段与大纲标题偏移
│   │   └── storage/
│   │       ├── DocumentFiles.ets           选择、读写、持久授权
│   │       └── LocalState.ets              最近文稿、草稿、外观偏好
│   └── resources/rawfile/                  构建写入的预览页与许可证文本
├── renderer/                               离线预览的源码与构建脚本
│   ├── index.html                          预览页外壳
│   ├── vite.config.ts                      打包为单个 HTML
│   ├── src/main.ts                         按格式 ID 分发并接收更新
│   ├── src/renderers/                      plain、markdown、svg、tex-math
│   ├── src/styles.css                      预览主题
│   └── scripts/                            复制预览页、生成许可证声明
├── docs/                                   架构、功能目录、结构、隐私、上架
├── examples/                               markdown、svg、tex 示例
├── third_party/README.md                   直接依赖与许可证选择
├── README.md                               产品概览
├── CONTRIBUTING.md                         构建、签名与提交
├── AGENTS.md                               改代码时的项目边界
├── build-profile.example.json5             公共构建配置模板
├── hvigorfile.ts                           应用构建入口
└── oh-package.json5                        OHPM 工程描述
```

## 常见改动的落点

| 要改什么 | 改哪里 |
| --- | --- |
| 首页、编辑、查找、菜单、主题 | `entry/src/main/ets/pages/Index.ets` |
| 打开、保存、草稿恢复 | `entry/src/main/ets/document/DocumentService.ets` |
| 文件授权与字节指纹 | `entry/src/main/ets/storage/DocumentFiles.ets` |
| 编码、BOM、换行 | `entry/src/main/ets/document/TextEncoding.ets` |
| 新增文稿格式 | 在 `document/FormatRegistry.ets` 登记扩展名、UTD 和 MIME，在 `module.json5` 的 `FileOpen` 中加入相同类型，并补充对应的预览渲染器 |
| 预览渲染 | `renderer/src/renderers/` |
| 预览样式 | `renderer/src/styles.css` |

`entry/src/main/resources/rawfile/preview/index.html` 由构建复制生成，不要直接编辑。修改渲染后重新构建即可。

## 不进入版本库的本地文件

- `build-profile.json5`：本机调试签名配置
- `~/.ohos/config/`：证书、描述文件和密钥库
- `.hvigor/`、`entry/build/`：构建缓存与产物
- `renderer/node_modules/`、`renderer/dist/`：依赖与预览构建输出

调试签名、证书和密钥库只保留在本机。
