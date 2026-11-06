# 上游许可证材料

`manifest.json` 将已核验的依赖版本映射到许可证原文及其上游声明，并记录来源和 SHA-256。构建时按包名、版本和许可证匹配并验证文件；找不到材料时仍会失败。

`hast@1.0.0` 的 npm 发布包只有 `package.json` 和重命名说明，没有运行代码或单独的许可证文件。其原始 `package.json` 声明了 MIT、作者和贡献者；构建收录这份原文件与 SPDX 的 MIT 标准原文，不自行填写版权年份。

`mdast@3.0.0` 和 `trie-prefix-tree@1.5.1` 的上游版本只提供 MIT 声明和署名，没有单独的完整条款文件。构建同时收录与 npm 包逐字比对过的上游 README，以及 SPDX 发布的 MIT 标准原文；标准文本保留原有占位符，不推测版权年份。缺少对应版本的署名声明时构建失败。

`eastasianwidth@0.2.0` 的维护者在上游 [授权说明](https://github.com/komagata/eastasianwidth/blob/f42b1e7b2a403d2050dda1141211b4e198e50e70/LICENSE-NOTES.md) 中专门确认了该历史版本。构建会同时收集完整许可原文及这份说明。

`boolbase@1.0.0` 的许可证来自维护者确认与 npm 包代码一致的上游源码；实际代码已逐字比对。

`spdx-exceptions@2.5.0` 和 `spdx-license-ids@3.0.24` 分别使用 Creative Commons 发布的 CC BY 3.0 和 CC0 1.0 法律文本；随附的上游版本 README 保留许可声明和署名。CC BY 项缺少经校验的署名声明时构建失败。

`argparse@2.0.1` 声明的 `Python-2.0` 是包含多项许可的完整 Python 许可，与 `PSF-2.0` 不能混同。构建保留发布包原始许可证和对应版本 README 中的移植说明；缺少经校验的说明时构建失败。
