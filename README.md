# discourse-seek · 觅电

Discourse 原生校园美食插件。Ruby 后端、数据库迁移、论坛账号权限、通知铃铛和前端均在插件内运行，不依赖旧 Next.js 服务。

## 功能

- 发现首页：推荐、热榜、有图、推荐菜、便宜、新维护；区域筛选与换一批。
- 店铺目录：关键词、分类、价格区间、评分、营业状态与排序。
- 门店详情：介绍、原始推荐语、人均、评分、推荐菜、分层点评、相册、共建历史、相关门店、链接分享和 PNG 分享卡片。
- 点评评分、体验标签、配图、回复、点赞、删除、举报；推荐菜与必点/一般/避雷标签。
- 论坛账号收藏；游客本地收藏。
- 新店投稿、资料修改、管理员审核、字段对照、版本冲突确认、暂停营业、可见性管理、举报处理、Markdown 关于页面和操作记录。
- 原生论坛通知，以及账号合并、匿名化和删除处理。
- 适应论坛的浅色/深色主题与移动端；安装校友地图插件时自动加入「校园生活」共同侧栏。

## 安装

将下面仓库加入 Discourse Docker 容器配置的插件安装步骤，固定经过验收的提交，然后按站点部署流程构建并滚动更新：

```yaml
- git clone https://github.com/InternationalRiversiders/discourse-seek.git
```

代码通过 Discourse 的插件与资源构建加载，表结构由 Rails migrations 管理。不能只向运行容器复制源码就视为正式安装完成。

后台设置：

| 设置 | 默认值 | 用途 |
| --- | --- | --- |
| `food_enabled` | false | 启用插件 |
| `food_read_only` | true | 只读预览，同时禁止写入及通知发送 |
| `food_admin_only` | false | 限制为管理员验收 |
| `food_public_browse` | true | 允许游客读取公开门店和点评 |
| `food_allowed_groups` | 空 | 可投稿、点评和收藏的论坛组；管理员始终可用 |
| `food_admin_groups` | 空 | 可审核与管理的论坛组 |

访问 `/food`。前端展示不替代后端鉴权，所有写入均检查启用状态、只读状态与用户组。

## 数据迁移

先备份旧库、旧图片和目标论坛库，在**独立数据库**演练。首次导入只允许空插件表；关闭 `food_enabled` 后应用。不要把两台共享生产数据库的 Web 当作两个测试站。

旧服务导出（凭据由执行环境注入，不写进命令记录或版本库）：

```sh
node script/export_legacy.mjs /path/to/old/eating-app /private/seek.json /path/to/old/images
```

导出器从 `LEGACY_DATABASE_URL` 获取只读连接，在 Repeatable Read 事务中读取。JSON 与图片 sidecar 必须一起保存；图片按 SHA256 验证。默认遇到缺图即停止。核实旧存储确实缺失后，可设置 `FOOD_EXPORT_ALLOW_MISSING_MEDIA=1`，显式记录缺图而不删除原始引用。

在装好插件的 Discourse 容器内：

```sh
bundle exec rails runner plugins/discourse-seek/script/import_legacy.rb /private/seek.json
RIVER_IMPORT_APPLY=1 RIVER_IMPORT_SHA256=REVIEWED_SHA256 bundle exec rails runner plugins/discourse-seek/script/import_legacy.rb /private/seek.json
```

导出中存在已核实缺图时，还需 `RIVER_ALLOW_MISSING_MEDIA=1`。预演会回滚全部插件数据，正式导入要求匹配文件哈希；同一文件再次执行不会重复创建数据。导入不会补发旧通知。

身份规则：

- 旧 `discourse:<id>` 仅关联目标论坛中确实存在的相同用户编号。
- GitHub 历史账号及已不存在的论坛账号仅保留历史署名与内容，以独立历史标识保存。**不创建论坛 User、不保留 GitHub 登录、OAuth、密码或旧会话接口。**
- 禁止按相似用户名猜测所有权。新互动统一使用当前论坛账号及用户组权限。

门店编号保持不变；旧 URL 可通过 `/food/legacy/shops/<id>` 等兼容路由解析。待审核修改保留申请前后的资料，首次审核强制核对版本差异。

旧站收藏导入、个人数据导出及对应页面入口已移除。论坛账号收藏和游客本地收藏继续使用；离线迁移工具仅用于灾难恢复演练。

## 备份与公开仓库

`river_food_*` 表（包括历史档案和经过处理的图片二进制）位于论坛 PostgreSQL，随论坛完整数据库备份与恢复。仍应保留旧站最后一次数据库和图片备份；代码与容器部署配置另行版本管理。定期执行恢复演练。

本仓库只包含代码、文档和虚构测试，不包含用户导出、图片副本、论坛备份、登录凭据或 API 密钥。实际迁移产物必须保存在仓库外的受限目录。

## 验证

`script/regression_test.rb` 只能在设置 `RIVER_DISPOSABLE=1` 且数据库名为 `river_community_test` 的一次性环境运行；会清空该库的 `river_food_*` 表。覆盖权限、只读与幂等、评分和回复、通知、媒体权限、审核冲突、收藏、账号生命周期和历史身份导入。

部署验收还应对照旧服务实际实现核对全部门店、评分、筛选与排序，校验图片、父子回复和历史署名，并用浏览器分别验证访客、校友、管理员、只读预览和深浅主题。

## 正式运行状态

已完成正式迁移，旧域名保留跳转，业务数据和图片由论坛数据库承接。当前功能核对与迁移边界见 [最终复核](docs/final-review.md)。
