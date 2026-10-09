# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------
# Lite Arcade 生产镜像：多阶段构建，最终产物为纯静态 nginx 容器
#   docker build -f deploy/Dockerfile -t lite-arcade:latest .
#   docker run --rm -p 8080:8080 lite-arcade:latest
# ---------------------------------------------------------------

# ---- Stage 1: 构建（无第三方依赖，仅做占位符替换与资产生成）----
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04 AS build
WORKDIR /work
COPY config ./config
COPY src ./src
COPY deploy/build.ps1 ./deploy/build.ps1
ENV PSDisableErrorColor=1
RUN pwsh -NoProfile -Command \
    "$ErrorActionPreference='Stop'; \
     ./deploy/build.ps1; \
     if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }"

# ---- Stage 2: 运行 ----
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=build /work/dist /usr/share/nginx/html
COPY deploy/nginx.conf /etc/nginx/nginx.conf

# nginx-unprivileged 默认监听 8080，与 nginx.conf 一致
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/ >/dev/null || exit 1

LABEL org.opencontainers.image.title="Lite Arcade" \
      org.opencontainers.image.description="零依赖静态开源游戏站（SEO + GEO 优化）" \
      org.opencontainers.image.source="https://github.com/ahujasid/blender-mcp"
