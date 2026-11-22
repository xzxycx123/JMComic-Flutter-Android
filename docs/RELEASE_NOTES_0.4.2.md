# JMComic v0.4.2

> 部分按钮切换至药丸，修复UI上的bug，添加功能
## 功能更新
1. JMCoin显示
2. 可在详情页搜索作者
3. 作品左下方显示点赞数
4. 添加签到功能，同步服务器
5. 主页作品点赞量显示（0.4.2 修复为 JmAPI `/album.likes`，见 `docs/LIKES_SOURCE.md`）
6. 阅读器UI美化
7. 按钮改为药丸

## Bug修复
- 首页点赞量改走 JmAPI `/album.likes`（网页压缩写法 21K 被解析成 21 的问题），首页/搜索/收藏与详情页数值一致
- 修复左上角标签问题
- 签到日历（存在问题）；阅读进度保存；左上角jm号
- 下载页的滑块改成可拖动
- 部分二级页面隐藏Docker栏
## 校验

```powershell
flutter analyze                       
flutter test                           # 151 passed / 2 skipped（实网用例需 JM_LIVE=true）
flutter build apk --release            
```

（这次Readme依旧是我自己写的喵）