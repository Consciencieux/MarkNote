# 构建与贡献

## 开发环境

- DevEco Studio 26 和 HarmonyOS SDK API 26。
- Node.js 22.12 或更新版本，以及 npm。

项目约束见 [AGENTS.md](AGENTS.md)，功能与已知限制见[功能目录](docs/FEATURES.md)。

建议在开发电脑上安装 DevEco CLI，以便从命令行构建、运行和调试应用，以及查询鸿蒙开发文档。安装前请准备好上述 DevEco Studio 和 Node.js 环境，然后在终端安装稳定版并检查版本：

```sh
npm install -g @deveco/deveco-cli@stable
devecocli --version
```

已安装的 DevEco CLI 可通过 `devecocli update` 更新。Linux 环境还需要配置工具链路径；安装条件、环境配置及其他安装方式见华为的 [DevEco CLI 快速入门](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-deveco-cli-install)。

## 构建离线预览

在仓库根目录执行：

```sh
cd renderer
npm ci
npm run check
npm run build
```

`npm ci` 安装锁定的 npm 依赖后，会从固定的 GitHub 提交获取 `tex-to-myst` 的两处修复，校验并编译到本机依赖目录。首次安装需要访问 npm 镜像和 GitHub；已验证的修复源码缓存在 `renderer/.cache/`，不提交到版本库。缓存及 npm 包齐全时可离线安装。修复的来源和移除条件见[第三方组件与许可证](third_party/README.md)。

构建生成单文件预览页，并从已安装的生产依赖中收集许可证：

- `entry/src/main/resources/rawfile/preview/index.html`
- `entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt`
- `entry/src/main/resources/rawfile/licenses/LICENSE`：仓库根目录 `LICENSE` 的副本。

不要手工修改这些生成文件来绕过构建。依赖的许可证缺失或不在脚本允许的范围内时，构建会失败；应先检查依赖及其许可证。依赖变更时一并更新 `package-lock.json`。

## 构建应用

用 DevEco Studio 打开仓库根目录，同步 OHPM 并构建 `entry` 模块。也可以在仓库根目录使用 DevEco CLI：

```sh
devecocli build --modules entry
```

## 本地配置与签名

首次克隆后，从模板创建本地构建配置：

```sh
cp build-profile.example.json5 build-profile.json5
```

在 DevEco Studio 中配置本机调试签名。真机安装需要为 `default` 产品配置可用的签名。公共构建配置发生变化时，同步更新模板。不要提交本机的签名证书、Profile、密钥库或口令。

## 验证

修改预览代码后，执行本页的预览检查与构建；修改 ArkTS 后，构建 `entry`。涉及界面或设备行为时，按改动范围进行运行验证，并在说明中区分已验证和未验证的部分。

用户功能发生变化时，同步更新[功能目录](docs/FEATURES.md)。不要提交 HAP、构建缓存、`renderer/node_modules/` 或 `renderer/dist/`。

## 发布源码版本

更新 `AppScope/app.json5` 中的 `versionName` 并递增 `versionCode`，在 [CHANGELOG.md](CHANGELOG.md) 中编写该版本的更新日志。提交后推送与版本号一致的标签，例如 `v0.1.0`。GitHub Actions 会用对应日志创建 Release，GitHub 自动提供源码压缩包。当前工作流不构建或上传安装包；安装包需要另行准备适用于目标分发方式的签名。
