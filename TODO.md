# 待办

## 优先修复

- [x] **从首页删除正在编辑的文稿**　在首页长按或多选删除当前文稿时，复用文稿页的删除保护。弹出确认框前同步输入，确认后暂停编辑并复核会话与正文。若正文已变，重新询问。[首页删除入口](entry/src/main/ets/pages/Index.ets) · [文稿页删除流程](entry/src/main/ets/pages/DocumentView.ets)
- [ ] **持久授权回滚（F06）**　区分查到的已有授权和本次实际新增的权限。核对权限查询失败后重查、打开取消、读取失败及会话切换时的结果。已有读权限升级为读写后若取消打开，应只撤销新增的写权限。[文件授权](entry/src/main/ets/storage/DocumentFiles.ets)
- [x] **批量移除记录后保留失败项的选中状态**　部分移除失败时，成功项从最近列表移除，失败项保持选中，可直接重试。全部成功后退出多选。[批量移除](entry/src/main/ets/pages/Index.ets)

## 文件与图片验收

- [x] **保存与草稿恢复**　三折叠模拟器上在写入部分正文后结束进程，重启遇到注入的草稿读取错误，重试恢复完整编辑正文。外部修改触发保存冲突且原文件未被覆盖。关闭文稿和新建换篇遇到注入的清理错误时，均保留原文稿并提示。[文稿服务](entry/src/main/ets/document/DocumentService.ets) · [此前故障场景](https://github.com/Consciencieux/MarkNote/pull/30)
- [x] **分享缓存（F08）**　三折叠模拟器上通过系统分享面板另存为，接收文件与分享正文逐字节一致。准备失败时移除了本次目录。注入面板与清理失败后，后续分享回收了模拟超过七天的副本。[文稿分享](entry/src/main/ets/document/DocumentShare.ets)
- [x] **图片解码中途换篇（N01）**　三折叠模拟器上在 Image Kit 解码开始后切换预览文稿，新预览只显示新正文。旧请求返回后丢弃缩略图，确认未交给 ArkWeb 的文件描述符已关闭。[图片响应](entry/src/main/ets/pages/DocumentPreviewView.ets)
