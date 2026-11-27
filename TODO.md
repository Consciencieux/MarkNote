# 待办

## LaTeX 预览

- [ ] **TikZ 图块不截入图外正文。** `start.offset` 与 `end.offset` 都是数字且落在源码范围内时，`tikzpicture` 仍只截取该环境。offset 为 `undefined` 时不得调用 `slice`，缺省端点会把图块外的正文截进来。得不到合法范围时不建立图块。正常 `.tex` 尚未复现位置缺失，验收用构造出的位置覆盖。[环境处理器](renderer/src/renderers/tex.ts)
- [ ] **端点对象缺失不拖垮整篇预览。** `start` 或 `end` 对象本身缺失时，读取 `.offset` 会抛错，整篇预览会被换成失败。`node.position` 整体缺失时同样不建立图块。环境处理器接住这两支，不向外抛。这与 offset 缺省截取是两条路径。[环境处理器](renderer/src/renderers/tex.ts)
- [ ] **保留部分 TikZ 图形时标明不完整。** 线段后的未知命令目前只产生 `unsupported-statement` 警告，继续输出仍能得到线段，Worker 却在求值后返回空，整幅改为显示源码。这是首版遇到不支持内容就显示源码的策略。若改为留下已画出的部分，预览必须同时提示图不完整，避免漏画被当成原图。解析和求值诊断有 `severity`，`emitSvg` 的诊断没有，不能对三个阶段用同一套级别过滤。[Worker](renderer/src/renderers/tikz.worker.ts)

## 界面布局

- [x] **平板首页菜单宽度验收**。在 MatePad 11.5″S 上核对了简体中文、俄语的首页更多、排序子菜单及文稿长按菜单。俄语长文案换行后可以完整显示。[菜单宽度](entry/src/main/ets/pages/MenuMaterialOptions.ets)
