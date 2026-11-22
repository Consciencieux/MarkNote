# 待办

## 界面布局

- [ ] **代码高亮页的「主题」标题**。标题目前由空卡片组承载，再将卡片设为透明、清零内边距。简化分组结构，核对标题仍在代码高亮二级页的主题选项卡片上方，与列表对齐。[设置子页](entry/src/main/ets/pages/SettingsDetail.ets)
- [ ] **首页菜单宽度**。首页更多和文稿长按菜单都固定为 `224vp`。核对各受支持设备及窗口是否适用华为的泛手机宽度规则，按适用场景保留固定宽度或交由组件适配内容。[首页更多](entry/src/main/ets/pages/DocumentMenus.ets) · [文稿长按](entry/src/main/ets/pages/HomeView.ets) · [华为菜单指南](https://developer.huawei.com/consumer/cn/doc/design-guides/menu-0000001957001877/)
- [ ] **文稿悬浮页签避让**。编辑、预览和大纲共用系统页签高度资源加底边距的计算。核对计算值与 `HdsTabs` 实际悬浮栏范围是否一致。各页签滚至末尾时，最后一行可移到页签上方，分栏两侧的底部避让一致。[避让计算](entry/src/main/ets/pages/DocumentScrollLayer.ets) · [华为 HdsTabs API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs)
