# 待办

## 优先修复

- [ ] **首页长按菜单与文稿删除**　在“全部”和“收藏”中操作的对象应是长按的文稿。删除正在编辑的文稿时，复用文稿页的确认流程：先同步输入，用户确认后暂停编辑并复核会话和正文；确认期间内容有变时重新询问。核对分享使用已保存内容、另存副本保留原件、移除记录保留文件。[首页功能分支](https://github.com/Consciencieux/MarkNote/tree/feature/home-document-actions)
- [ ] **持久授权回滚（F06）**　区分查到的已有授权和本次实际新增的权限。核对权限查询失败后重查、打开取消、读取失败及会话切换时的结果。已有读权限升级为读写后若取消打开，应只撤销新增的写权限。[文件授权](entry/src/main/ets/storage/DocumentFiles.ets)
- [ ] **首页多选与批量操作**　把每项记录操作的结果返回给多选界面。批量移除部分失败时，成功项从列表移除，失败项保持选中以便重试。核对进入和退出多选、批量分享、收藏和删除；另存副本仅用于单篇文稿。两项首页修复完成后，将 `feature/home-document-actions` 合入 `dev`。

## 文件与图片验收

- [ ] **保存与草稿恢复**　核对写入中断后重启能恢复编辑正文，文件被外部修改后保存会拒绝覆盖。草稿暂时读不出时应保留原件供重试；放弃或换篇时清理失败，应保留当前文稿并提示。[文稿服务](entry/src/main/ets/document/DocumentService.ets) · [已验故障场景](https://github.com/Consciencieux/MarkNote/pull/30)
- [ ] **分享缓存（F08）**　确认接收方能读取已分享的临时副本；分享准备或面板打开失败时检查本次副本是否清理，清理失败时检查后续分享能否回收超过七天的副本。[文稿分享](entry/src/main/ets/document/DocumentShare.ets)
- [ ] **图片解码中途换篇（N01）**　在缩略图仍在解码时切换文稿，确认旧图不会出现在新文稿中，取消的请求会关闭尚未交给 ArkWeb 的文件描述符。[图片响应](entry/src/main/ets/pages/DocumentPreviewView.ets)
