# AGENTS

先读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。构建命令和提交范围在 [CONTRIBUTING.md](CONTRIBUTING.md)，产品能力边界在 [README.md](README.md)。不要把这三份说明互相抄一遍。

改动时守住这些边界：

- 导航、编辑、查找、大纲、主题、文件菜单留在 ArkUI。ArkWeb 只渲染离线预览，不往页面注册 ArkTS 接口。
- 不增加 `ohos.permission.INTERNET`，不从 CDN 拉脚本、字体或图片。
- 用户文件继续走系统选择器返回的 URI。最近文稿要持久化并在下次启动时激活授权，不要改成复制进应用沙箱来代替原文件。
- 不编造签名、证书、隐私政策 URL、商店资质或审核结论。签名材料不进 git。
- 包名保持 `AppScope/app.json5` 里的值，除非使用者明确要求更换。
- 第三方 NOTICE 只由 `renderer` 的构建脚本生成。缺许可证时让构建失败，不要放宽后悄悄省略。
- 首页标题栏不再放「新建」「打开」。编辑页的保存、查找、更多使用系统符号图标。
- 没有在真机上走过的路径，不要写成已经验证。
