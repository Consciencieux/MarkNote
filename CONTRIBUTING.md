# 参与构建

需要 DevEco Studio 26、HarmonyOS SDK API 26、Node.js 22.12 或更新版本，以及 npm。

## 预览页

```sh
cd renderer
npm ci
npm run check
npm run build
```

`npm run build` 生成单文件预览页，并从当前安装的生产依赖收集许可证和 NOTICE，复制到：

```text
entry/src/main/resources/rawfile/preview/index.html
entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt
```

许可证缺失或类型不在允许范围内时，构建会停。不要手写那份 NOTICE 来代替脚本输出。`package-lock.json` 要随依赖变更一起提交，之后用 `npm ci` 重现同一棵依赖树。

## 应用

用 DevEco Studio 打开仓库根目录并同步 OHPM。包名是 `com.zhouyi.marknote`，写在 `AppScope/app.json5`。

## 本地构建配置与签名

仓库使用 `build-profile.example.json5` 保存公共构建配置，实际使用的 `build-profile.json5` 不参与 Git 版本控制。

首次克隆仓库后，在项目根目录执行：

```sh
cp build-profile.example.json5 build-profile.json5
```

随后在 DevEco Studio 中配置本机调试签名。

`build-profile.json5` 已加入 `.gitignore`，DevEco Studio 自动生成的签名设置不会进入版本控制。修改 SDK、产品等公共构建配置时，应同步更新模板。

签名证书、Profile、密钥库和口令不得提交到仓库。真机安装前，产品 `default` 需要引用这份本地签名，否则打出来的是未签名 HAP。

## 提交前

- 预览相关改动先跑 `renderer` 的 `npm run check`，再跑 `npm run build`。
- ArkTS 改动用 DevEco 或 hvigor 编过 `entry`。
- 新增、改变或移除用户功能时，在相同改动中更新 [功能目录](docs/FEATURES.md) 对应条目；不把尚未完成的功能登记为现有能力。
- 不把 `.hap`、`renderer/node_modules/`、`renderer/dist/` 或本机签名材料放进提交。
