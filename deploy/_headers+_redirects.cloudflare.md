# Cloudflare Pages 静态托管
# ---------------------------------------------------------------
# 1) 在 Pages 项目中设置构建命令：pwsh -NoProfile -Command ./deploy/build.ps1
# 2) 构建输出目录：dist
# 3) 本文件定义生产环境的安全头与缓存策略
# ---------------------------------------------------------------

/assets/*
  X-Content-Type-Options: nosniff
  Cache-Control: public, max-age=31536000, immutable

/*.html
  Cache-Control: no-cache, must-revalidate

/llms.txt
  Cache-Control: public, max-age=86400

/llms-full.txt
  Cache-Control: public, max-age=86400

/sitemap.xml
  Cache-Control: public, max-age=3600

/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: SAMEORIGIN
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: geolocation=(), microphone=(), camera=()
  Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; font-src 'self' data:; connect-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'self'

# 目录尾斜杠规范化（避免重复内容影响 SEO）
/games        /games/   301
/about        /about/   301
