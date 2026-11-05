# 参与构建

## 环境

- DevEco Studio 26
- HarmonyOS SDK API 26
- Node.js 22.12 或更新版本，以及 npm

## 构建预览页

```sh
cd renderer
npm ci
npm run check
npm run build
```

`npm run build` 生成单文件预览页，同时从当前安装的生产依赖中收集许可证，写入以下位置：

```text
entry/src/main/resources/rawfile/preview/index.html
entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt
entry/src/main/resources/rawfile/licenses/LICENSE
```

`licenses/LICENSE` 是仓库根目录 `LICENSE` 的原样副本，供设置里的「本项目开源许可证」离线阅读。不要改这份副本，也不要把它写进 `THIRD_PARTY_NOTICES.txt`。

许可证缺失，或者许可证类型不在允许范围内时，构建会失败。不要手工编写 `THIRD_PARTY_NOTICES.txt` 来绕过这一步。`package-lock.json` 随依赖变更一起提交，之后用 `npm ci` 还原同一棵依赖树。

## 构建应用

用 DevEco Studio 打开仓库根目录，同步 OHPM 后构建 `entry` 模块。包名为 `com.zhouyi.marknote`，定义在 `AppScope/app.json5`。

## 本地构建配置与签名

仓库只提交公共构建配置模板 `build-profile.example.json5`，实际使用的 `build-profile.json5` 已被 `.gitignore` 排除。首次克隆后执行：

```sh
cp build-profile.example.json5 build-profile.json5
```

然后在 DevEco Studio 中配置本机调试签名。修改 SDK、产品等公共构建配置时，同步更新模板。

签名证书、Profile、密钥库和口令不得提交。真机安装前，产品 `default` 需要引用本地签名，否则产物是未签名 HAP。

## 提交前

- 改动涉及预览时，在 `renderer/` 执行 `npm run check`，再执行 `npm run build`。
- 改动涉及 ArkTS 时，用 DevEco Studio 或 hvigor 编译 `entry`。
- 新增、修改或移除用户功能时，在同一次改动里更新[功能目录](docs/FEATURES.md)的对应条目。
- 不要把 `.hap`、`renderer/node_modules/`、`renderer/dist/` 或本机签名材料放进提交。
