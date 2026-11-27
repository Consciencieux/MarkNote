# 待办

## LaTeX 预览

- [ ] **保留部分 TikZ 图形时标明不完整。** 线段后的未知命令目前只产生 `unsupported-statement` 警告，继续输出仍能得到线段，Worker 却在求值后返回空，整幅改为显示源码。这是首版遇到不支持内容就显示源码的策略。若改为留下已画出的部分，预览必须同时提示图不完整，避免漏画被当成原图。解析和求值诊断有 `severity`，`emitSvg` 的诊断没有，不能对三个阶段用同一套级别过滤。[Worker](renderer/src/renderers/tikz.worker.ts)
