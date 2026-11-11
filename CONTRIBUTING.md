# 参与 MarkNote 开发

感谢你对 MarkNote 的关注！欢迎报告问题、提出建议，也欢迎改进代码和文档。

## 开始开发

### 开发环境

| 工具 | 版本 |
| --- | --- |
| DevEco Studio | 26 |
| HarmonyOS SDK | API 26 |
| Node.js | 22.12 或更新版本 |

项目也需要 npm。建议安装 DevEco CLI，用于构建、运行和调试应用，以及查询鸿蒙开发文档：

```sh
npm install -g @deveco/deveco-cli@stable
devecocli --version
```

已安装的 CLI 可通过 `devecocli update` 更新。Linux 工具链配置及其他安装方式见华为的 [DevEco CLI 快速入门](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-deveco-cli-install)。

### 获取项目并配置签名

```sh
git clone https://github.com/Consciencieux/MarkNote.git
cd marknote
cp build-profile.example.json5 build-profile.json5
```

用 DevEco Studio 打开项目，在本机构建配置中设置调试签名。真机安装需要为 `default` 产品配置可用的签名。如果公共构建配置发生变化，请同步更新 `build-profile.example.json5`；本机配置、证书、Profile、密钥库和口令不提交到版本库。

### 构建项目

应用的离线预览由 `renderer/` 构建。首次使用时，在该目录安装依赖：

```sh
cd renderer
npm ci
```

安装过程会从固定的 GitHub 提交获取、校验并编译 `tex-to-myst` 的两处修复。首次安装需要访问 npm 镜像和 GitHub；依赖与修复缓存齐全时可以离线安装。修复来源和移除条件见[第三方组件与许可证](third_party/README.md)。

修改预览或依赖后，在 `renderer/` 执行：

```sh
npm run check
npm test
npm run build
```

预览构建生成 `entry/src/main/resources/rawfile/preview/index.html` 和 `entry/src/main/resources/rawfile/licenses/` 中的许可证文本，供应用打包。这些生成文件纳入版本库；依赖变化时还需更新 `renderer/package-lock.json`。缺少有效许可证材料时构建会失败，应检查依赖及其授权材料，不要手工修改生成文件绕过检查。

在 DevEco Studio 中同步 OHPM 并构建 `entry` 模块，或在仓库根目录使用 DevEco CLI：

```sh
devecocli build --modules entry
```

### 项目结构

`entry/` 包含鸿蒙应用，`renderer/` 包含离线预览源码。目录和常见改动的位置见[仓库结构](docs/STRUCTURE.md)，模块职责见[架构](docs/ARCHITECTURE.md)。

## 开发流程

### 分支

`dev` 用于集成下一版本，`main` 保存已发布版本。新功能和普通修复从最新 `dev` 创建 `feature/xxx` 或 `fix/xxx` 分支，并通过 PR 合并到 `dev`。需要立即修复已发布版本时，从 `main` 创建 `hotfix/xxx` 分支。

功能和普通修复使用 Squash merge。合并后删除短期分支，后续工作从最新 `dev` 创建新分支。

### 发布

版本号、更新日志和标签的关系见[项目开发约定](AGENTS.md)。发布标签必须指向 `main` 历史中的提交，并与 `AppScope/app.json5` 的应用版本及 `CHANGELOG.md` 中的版本标题一致。推送 `vX.Y.Z` 标签后，Release 工作流会校验这些条件，在 GitHub 托管的 Runner 上检查、测试并重建预览资源，确认生成文件与标签一致后创建草稿。工作流不构建 HAP，也不自动发布。

在标签对应的源码提交上本机构建未签名 debug HAP：

```sh
git switch --detach vX.Y.Z
cp build-profile.example.json5 build-profile.json5
rm -rf entry/build build .hvigor dist
devecocli build --product default --modules entry --build-mode debug
```

在 `entry/build/default/outputs/` 中确认只生成一个 `*-unsigned.hap`，将它命名为 `MarkNote-vX.Y.Z-unsigned.hap`。可用 `shasum -a 256 MarkNote-vX.Y.Z-unsigned.hap > SHA256SUMS` 生成校验文件。把 HAP 和 `SHA256SUMS` 上传到工作流创建的草稿 Release，检查版本、更新日志与附件后，再手动发布。该 HAP 可在兼容的模拟器中验证；真机安装需要自行配置调试签名。签名材料不进入仓库或 Release。

正在发布的版本日志不能再写「安装包将另行发布」。

### 提交 Pull Request

1. 从对应基线创建分支并完成修改。
2. 按改动范围构建和验证；如果影响用户功能或使用限制，同步更新[功能目录](docs/FEATURES.md)和应用内使用帮助。
3. 提交 PR，说明改动内容、原因和验证结果；涉及设备行为时，注明使用的设备或模拟器及未验证的部分。

不要提交 HAP、构建缓存、`renderer/node_modules/` 或 `renderer/dist/`。

## 代码与界面约定

项目使用 ArkUI 实现导航、编辑和文件操作，使用 ArkWeb 渲染离线预览。页面、文件访问和网络使用的约束见 [AGENTS.md](AGENTS.md)；新增或修改界面时，请按其中的要求查阅华为官方文档并优先使用系统组件和资源。

## 测试

修改 ArkTS 后构建 `entry`；修改预览或依赖后执行上面的预览检查、测试和构建。涉及界面或设备行为时，还需要在设备或模拟器上验证相关操作，编译通过不能代替运行验证。

## 参与贡献

可以在 [Issues](https://github.com/Consciencieux/MarkNote/issues) 中查看已有问题，或提交新问题和建议。报告问题时，请说明设备、系统版本、复现步骤和实际结果，以便定位。
