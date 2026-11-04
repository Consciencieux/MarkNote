# 仓库地图

这页只回答文件放在哪个目录。模块之间怎么配合，见 [ARCHITECTURE.md](ARCHITECTURE.md)。

```text
marknote
├── AppScope/app.json5                     包名与应用图标
├── entry/src/main/ets/
│   ├── entryability/EntryAbility.ets      桌面启动与系统打开文件
│   ├── pages/Index.ets                    首页、编辑、查找、主题
│   ├── document/LaunchRequests.ets        冷启动时暂存外部文件请求
│   ├── document/FormatRegistry.ets        扩展名、UTD、MIME、大纲
│   ├── document/DocumentService.ets       文稿会话、打开、保存、冲突
│   ├── document/TextEncoding.ets          编码、BOM、换行
│   ├── model/Document.ets                 文稿字段与标题偏移
│   └── storage/
│       ├── DocumentFiles.ets              选择、读写、持久授权
│       └── LocalState.ets                 最近文稿、草稿、主题偏好
├── entry/src/main/module.json5            Ability、FileOpen 与权限
├── entry/src/main/resources/rawfile/      打进 HAP 的预览页和声明
├── renderer/
│   ├── src/main.ts                        按格式 ID 调用渲染器
│   ├── src/renderers/                     plain、markdown、svg、tex-math
│   ├── src/styles.css                     预览主题
│   └── scripts/                           复制预览页并生成声明
├── docs/                                  架构、功能目录、隐私、上架
├── examples/                              markdown、svg、tex 示例
├── third_party/README.md                  直接依赖和许可证选择
├── README.md                              产品概览
├── CONTRIBUTING.md                        构建、签名和提交
├── build-profile.example.json5            公共构建配置模板
├── hvigorfile.ts                          应用构建入口
└── oh-package.json5                       OHPM 工程描述
```

## 源码从这里改

首页、编辑、查找和主题都在 `entry/src/main/ets/pages/Index.ets`。新增格式时，把扩展名、UTD 和 MIME 登记进 `document/FormatRegistry.ets`，并在 `module.json5` 的 `FileOpen` 里增加同一条类型。

打开、保存和切换文稿进入 `document/DocumentService.ets`。文件授权和字节指纹在 `storage/DocumentFiles.ets`。编码、BOM 和换行仍单独放在编码模块里。

预览页只接收格式 ID 和正文，分发入口是 `renderer/src/main.ts`。

```text
entry/src/main/ets/
├── pages/Index.ets                        菜单、编辑页、预览调度
├── document/FormatRegistry.ets            新格式先登记在这里
├── document/LaunchRequests.ets            系统文件请求
├── document/DocumentService.ets           打开、保存、草稿恢复
├── document/TextEncoding.ets              字节、BOM、换行
├── model/Document.ets                     大纲标题和文稿字段
├── storage/DocumentFiles.ets              授权、指纹、读写
└── storage/LocalState.ets                 草稿保留编码和换行
renderer/src/main.ts                       按格式 ID 分发
renderer/src/renderers/                    每种格式一个渲染文件
renderer/src/globals.d.ts                  预览消息里的格式 ID
```

`entry/src/main/resources/rawfile/preview/index.html` 是构建复制进来的预览页。改渲染后重新构建，不要直接改这个 HTML。

`examples/` 里有 `markdown.md`、`vector.svg` 和 `equation.tex`，用来对照三种格式。应用运行时不读这个目录。

## 离线预览怎么进包

`renderer/` 执行 `npm run build` 后写入 HAP。

```text
renderer/
├── index.html                             预览页壳
├── vite.config.ts                         打成单个 HTML
├── package.json                           markdown-it、KaTeX、DOMPurify
├── src/main.ts                            接收更新并做最终清理
├── src/styles.css                         浅色与深色预览
├── src/renderers/plain.ts                 .txt
├── src/renderers/markdown.ts              .md 与 .markdown
├── src/renderers/svg.ts                   .svg
├── src/renderers/tex-math.ts              .tex 公式
└── scripts/
    ├── package-assets.mjs                 复制预览页，并调用声明脚本
    └── generate-notices.mjs               收集第三方声明
entry/src/main/resources/rawfile/
├── preview/index.html                     预览页的复制结果
└── licenses/THIRD_PARTY_NOTICES.txt       声明的复制结果
```

许可证缺失或类型不在允许范围时，`generate-notices.mjs` 会让构建停下。不要手写 `THIRD_PARTY_NOTICES.txt` 来代替脚本输出。

## 留在本地

```text
本地
└── 工作区里会有
    ├── build-profile.json5                调试签名配置
    ├── ~/.ohos/config/                    证书、描述文件、密钥库
    ├── .hvigor/                           构建缓存
        renderer/node_modules/
        renderer/dist/
        entry/build/
```

调试签名、证书和密钥库只留在本机。依赖目录、预览构建目录和 HAP 输出由工具生成，不要放进提交。
