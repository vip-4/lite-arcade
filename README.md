# Lite Arcade · 轻量开源游戏站

零依赖的静态开源网页游戏站：六款原生 HTML5 Canvas 小游戏 + 一份从四个公开来源筛选的开源游戏目录，内置完整的 SEO 与 GEO（生成式引擎优化）资产，并附带本地生产化部署配置。

- 构建后产物：纯静态文件，任意 HTTP 服务器 / CDN / 对象存储均可托管
- 运行时依赖：无（不使用 Node、Python 或任何打包工具）
- 游戏实现：贪吃蛇、2048、打砖块、俄罗斯方块、记忆翻牌、像素飞鸟，均小于 20 KB

## 快速开始

```powershell
# 1. 构建（生成 dist/）
.\deploy\build.ps1

# 2. 指定正式域名构建
.\deploy\build.ps1 -BaseUrl "https://your-domain.com"

# 3. 本地生产形态预览（默认 http://localhost:8080）
.\deploy\serve.ps1 -Root dist -Port 8080

# 4. 构建并直接拉起服务
.\deploy\build.ps1 -Serve -Port 8080
```

构建脚本会自动完成：占位符替换 → 生成 6 个游戏详情页 → 生成 `sitemap.xml` / `robots.txt` / `llms.txt` / `llms-full.txt` → 生产校验（元数据完整性、JSON-LD 可解析、内链可达性），校验失败会以非 0 退出码终止。

## 目录结构

```
config/                 站点与内容配置（构建期唯一数据源）
  site.json             站名、Base URL、关键词、主题色
  games.json            6 款游戏的元数据、玩法、操作、技巧、FAQ
  llms.json             GEO 事实清单与 FAQ
  game-template.html    游戏详情页模板（含 {{GAME_*}} 令牌与 {{#list}} 循环）
src/                    静态源码
  index.html            首页
  games/index.html      全部游戏
  about/index.html      关于与 GEO 说明
  404.html
  assets/               css / js / data / img
deploy/                 部署与工具
  build.ps1             生产化构建（校验 + 生成）
  serve.ps1             零依赖本地静态服务器
  gen-assets.ps1        生成 og-cover.png 与 PWA 图标
  check-js.js           用内置 JScript 引擎做 ES5 语法编译校验
  nginx.conf / Dockerfile / netlify.toml / vercel.json / _headers+_redirects.cloudflare.md
dist/                   构建产物（不入库）
```

## 部署形态

| 形态 | 配置文件 | 说明 |
| --- | --- | --- |
| 本地静态服务 | `deploy/serve.ps1` | .NET HttpListener，含 MIME、缓存策略、404 |
| Docker + nginx | `deploy/Dockerfile`、`deploy/nginx.conf` | 多阶段构建，最终为 nginx-unprivileged 镜像，监听 8080 |
| Netlify | `deploy/netlify.toml` | 构建命令 `pwsh ./deploy/build.ps1`，发布目录 `dist` |
| Vercel | `deploy/vercel.json` | `outputDirectory: dist`，含安全头与缓存规则 |
| Cloudflare Pages | `deploy/_headers+_redirects.cloudflare.md` | 按文件内容放入 `_headers` 与 `_redirects` |
| GitHub Pages | `.github/workflows/deploy.yml` | windows-latest 上构建 + JScript 语法校验 + Pages 发布 |
| 手动上传 / 对象存储 | `deploy/package.ps1` | 产出 `release/lite-arcade-dist-<时间戳>.zip` 与 `checksums.txt` |

```powershell
.\deploy\package.ps1     # 打包 dist，供任意静态托管或对象存储上传
```

## CI/CD

`.github/workflows/deploy.yml` 在推送到 `main` 时自动执行：

1. `deploy/gen-assets.ps1` 生成封面与图标
2. `deploy/build.ps1 -BaseUrl <站点地址>` 构建并执行生产校验
3. `deploy/check-js.js`（内置 JScript 引擎）做前端脚本语法编译校验
4. 上传 Pages 构件并发布；`workflow_dispatch` 时额外产出 `lite-arcade-dist` 分发包

Base URL 优先取 `vars.SITE_BASE_URL`（仓库变量），未设置时回退到 `https://<owner>.github.io/<repo>`。

## SEO 清单

- 每个页面：唯一 `<title>` / `meta description` / `canonical`，单一 `<h1>`
- Open Graph 与 Twitter Card 完整，含 1200×630 的 `og-cover.png`
- 结构化数据：`WebSite`、`Organization`、`WebPage`、`CollectionPage`、`AboutPage`、`ItemList`、`BreadcrumbList`、`VideoGame`、`HowTo`、`FAQPage`、`SpeakableSpecification`
- `sitemap.xml`（按页面类型设置 priority/changefreq）、`humans.txt`、`manifest.webmanifest`（PWA + 游戏快捷方式）
- 目录尾斜杠 301 规范化、安全响应头、静态资源长缓存 + HTML 不缓存

### 每页 meta 标签清单

`title` / `description` / `keywords` / `author` / `robots`（含 `max-image-preview:large`、`max-snippet:-1`）/ `googlebot` / `bingbot` / `theme-color` / `color-scheme` / `application-name` / `referrer` / `canonical`

- Open Graph：`og:type`、`og:site_name`、`og:locale`、`og:title`、`og:description`、`og:url`、`og:image`、`og:image:width`、`og:image:height`、`og:image:alt`
- Twitter Card：`twitter:card`、`twitter:site`、`twitter:creator`、`twitter:title`、`twitter:description`、`twitter:image`、`twitter:image:alt`、`twitter:label1/data1`、`twitter:label2/data2`
- GEO 入口：`<link rel="alternate" type="text/plain" href="/llms.txt">` 与 `/llms-full.txt`

## 语义化与可访问性

- 骨架：`<header>` / `<nav>` / `<main>`（每页唯一）/ `<article>` / `<aside>` / `<section>` / `<footer>`，每个区块带 `aria-labelledby`
- 标题层级：每页唯一 `<h1>`，构建期校验 `h3` 不得早于 `h2`
- 键盘可达：跳转链接 `skip-link`、全局 `:focus-visible` 描边、所有交互元素为原生 `button` / `a` / `input`
- 辅助技术：`aria-live="polite"` 的动态目录计数、`role="img"` 的画布、`lang="en"` 标注外文词、`scope` 标注的表头、`<caption>` 与 `<time datetime>`
- 视觉适配：`prefers-reduced-motion`、`prefers-contrast: more`、`forced-colors: active`、打印样式
- 构建期强制校验：缺少 `alt` 的 `<img>`、缺少 `<main>` / `<header>` / `<footer>` / `skip-link` 均会导致构建失败

## 性能

- 首页：HTML 20.7 KB + CSS 16.6 KB + JS（仅 `site.js` 约 10 KB）≈ 45 KB，全部为首屏关键资源
- 全站 **0 个外部加载资源**（0 个第三方字体、CDN、统计脚本）；页面中的 7 个外链均为出站锚文本，带 `rel="noopener nofollow external"`
- 游戏脚本按需加载（仅游戏详情页引入 `game-core.js` 与对应游戏脚本），全部 `defer`
- 系统字体栈、无阻塞渲染、目录长列表启用 `content-visibility: auto`
- 静态资源长缓存（1 年 immutable）+ HTML 不缓存；nginx 开启 gzip

## GEO（生成式引擎优化）清单

- `llms.txt` 与 `llms-full.txt`：站点摘要、事实清单、页面索引、FAQ
- `robots.txt` 显式放行 GPTBot、OAI-SearchBot、ChatGPT-User、ClaudeBot、Claude-User、Claude-SearchBot、PerplexityBot、Google-Extended、Applebot-Extended、Bingbot、CCBot、Amazonbot、cohere-ai、Diffbot
- 答案前置：每页首屏给出 40–60 字定义式摘要，配 `speakable` 与稳定锚点 `#answer` / `#faq`
- 实体一致性：站名、许可、技术形态全站统一表述
- 可核实性：目录数据标注采集来源与快照时间，不编造评分与评价
- 零外部请求、系统字体、无阻塞脚本

## 内容来源

| 来源 | 入口 | 采集方式 |
| --- | --- | --- |
| itch.io 开源榜 | https://itch.io/games/tag-open-source | 抓取列表页，按可核实条目人工筛选 |
| GitHub Trending | https://github.com/trending | 趋势页 + Search API（topic:game，按 star 排序），首页运行时实时拉取并回退快照 |
| Ludum Dare | https://github.com/orgs/LudumDare/repositories | Search API `topic:ludum-dare` |
| Simple Game Tutorials | https://simplegametutorials.github.io | 读取仓库目录树（LÖVE 与 Pygame Zero 双版本） |

第三方项目保留各自原许可，目录条目仅作索引，版权归原作者所有。

## 许可

站内自研游戏与页面代码以 MIT 许可发布。

## 注意事项

- 部署到正式环境前，请修改 `config/site.json` 的 `baseUrl`，或使用 `-BaseUrl` 覆盖，否则 canonical / og:url / sitemap 会保留默认值。
- 不要把任何 API 密钥、令牌写入仓库；如需服务端能力，请通过环境变量注入并在部署平台配置。
- PowerShell 5.1 读取无 BOM 的 UTF-8 脚本会按 ANSI 解码并导致中文被破坏，`deploy/*.ps1` 已统一写入 UTF-8 BOM，请勿移除。
