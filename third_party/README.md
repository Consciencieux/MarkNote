# 第三方组件与许可证

离线预览的直接依赖和版本在 [renderer/package.json](../renderer/package.json) 声明，完整依赖树及解析版本由 [package-lock.json](../renderer/package-lock.json) 锁定。运行 `npm ci` 将依赖安装到本机 `renderer/node_modules/`；该目录不提交。构建工具依赖与运行时依赖在 `package.json` 中分别列出。

`tex-to-myst` 暂时使用 npm 上的固定版本 `1.0.48`。安装脚本从 [固定的 GitHub 提交](https://github.com/Consciencieux/mystmd/commit/26c56a8dd27e7eb78e7c3b46eb2cd3bf30cfff1a) 获取两个修复后的源码文件，校验散列并用锁定版本的 TypeScript 编译到已安装的依赖目录；修复已向上游提交 [PR](https://github.com/jupyter-book/mystmd/pull/3128)。上游发布包含修复的版本后，应更新依赖并移除该安装步骤。修复文件的缓存不提交，构建和测试前会校验安装结果。

## 许可证材料与应用内声明

预览构建脚本从已安装的生产依赖收集许可证与 NOTICE。对于发布包缺少许可证原文或需要补充声明的依赖，[upstream-licenses](upstream-licenses/) 保存核实过的上游原文、版本对应关系及来源；脚本验证版本和文件散列后使用这些材料。依赖的许可证类型未经允许、材料缺失或校验失败时，构建会中止。

按[构建与贡献](../CONTRIBUTING.md)中的步骤构建后，脚本统一生成 `entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt`，供应用的“设置 → 开源许可证 → 第三方开源许可证”显示。本项目的 GPL-3.0 许可证单独由根目录 `LICENSE` 复制到应用资源中。两个应用资源均是生成文件，不应手工维护。

应用图标由本仓库绘制。发布时应另行核对商店素材、翻译文案及其他随应用分发的资源的使用权。
