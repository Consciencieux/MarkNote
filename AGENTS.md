# AGENTS

## 先读什么

改动之前先读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 了解模块职责，用 [docs/FEATURES.md](docs/FEATURES.md) 确认功能现状、限制和负责代码。构建方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，产品概览见 [README.md](README.md)。同一条信息只在一处维护，不要复制到多个文档。

## 拿不准时先查官方做法

如果某个问题改了多轮仍然不对，或者只能靠猜着往前改，先停下来确认自己是否偏离了官方做法。优先查阅官方文档和 SDK 接口说明，确认正确做法之后再改代码，不要凭感觉反复调整。

## 文档同步

新增、修改或删除用户可用的功能时，在同一次改动里更新 `docs/FEATURES.md` 的对应条目。只登记真正接入用户入口、可以实际操作的行为；还在开发中的功能留在 Issue 等任务渠道，不写进功能目录。

新增文稿格式时，`FormatRegistry`、对应的预览渲染器和功能目录需要一起修改。

## 项目边界

- 导航、编辑、查找、大纲、主题和文件菜单由 ArkUI 实现。ArkWeb 只渲染离线预览，不向页面注册 ArkTS 接口。
- 不申请 `ohos.permission.INTERNET`，也不从 CDN 加载脚本、字体或图片。
- 用户文件通过系统选择器或文件管理器返回的 URI 访问。最近文稿的 URI 需要持久化授权，不要改成把文件复制进应用沙箱。系统打开文件复用现有 `EntryAbility` 的 `viewData` / `FileOpen`，不新建 UIAbility，也不注册 `general.file`。
- 不编造签名、证书、隐私政策 URL、商店资质或审核结论。签名材料不进版本库。
- 包名以 `AppScope/app.json5` 为准，除使用者明确要求外不要更换。
- 第三方 NOTICE 只由 `renderer` 的构建脚本生成。缺少许可证时让构建失败，不要放宽规则或手工补写。
- 首页标题栏不放「新建」和「打开」。编辑页的保存、查找和更多入口使用系统符号图标。
- 没有在真机上验证过的路径，不要写成已经验证。
