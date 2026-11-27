# 待办

## LaTeX 预览

- [x] **TikZ 图块不截入图外正文。** 只接受位于源码范围内、起点严格小于终点的整数偏移。已验证缺省偏移、小数、`NaN`、空区间、反向区间及越界位置均会跳过图块，`examples/tikz.tex` 截出的环境与源码一致。[环境处理器](renderer/src/renderers/tex.ts)
- [x] **端点对象缺失不拖垮整篇预览。** `position`、`start` 或 `end` 为 `null` 或缺失时直接返回，不读取 `.offset`，不建立图块，也不向外抛。用构造位置覆盖了这几支。这与 offset 缺省截取是两条路径。[环境处理器](renderer/src/renderers/tex.ts)
- [ ] **保留部分 TikZ 图形时标明不完整。** 线段后的未知命令目前只产生 `unsupported-statement` 警告，继续输出仍能得到线段，Worker 却在求值后返回空，整幅改为显示源码。这是首版遇到不支持内容就显示源码的策略。若改为留下已画出的部分，预览必须同时提示图不完整，避免漏画被当成原图。解析和求值诊断有 `severity`，`emitSvg` 的诊断没有，不能对三个阶段用同一套级别过滤。[Worker](renderer/src/renderers/tikz.worker.ts)

## 界面布局

- [x] **平板首页菜单宽度验收**。在 MatePad 11.5″S 上核对了简体中文、俄语的首页更多、排序子菜单及文稿长按菜单。俄语长文案换行后可以完整显示。[菜单宽度](entry/src/main/ets/pages/MenuMaterialOptions.ets)
