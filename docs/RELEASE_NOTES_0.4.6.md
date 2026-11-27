# JMComic v0.4.6

> 进一步完善 Liquid Glass UI，优化详情页章节展示，修复阅读器图片保存问题。

## 功能更新

1. 主题选项更名为 Material / Liquid Glass
2. 详情页章节列表默认折叠，仅显示当前阅读章节及其前后各两章
3. 添加章节列表展开/收起功能，支持手动查看并选择全部章节

## Bug修复

- 修复登录界面提示框不符合 Liquid Glass 主题设计的问题
- 修复阅读器保存当前页时，Toast 提示保存成功但图片实际未保存的问题

## 校验

```powershell
flutter analyze
flutter test
flutter build apk --release
```

（这次Readme是AI帮我写的喵）