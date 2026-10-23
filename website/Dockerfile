# Build from the repo root, so the build can read docs/:
#   docker build -f website/Dockerfile -t bzide-website .
FROM python:3.13-alpine AS build
WORKDIR /repo
COPY docs/USER-GUIDE.md docs/PRIVACY.md docs/
COPY website/ website/
RUN python3 website/build.py

FROM nginxinc/nginx-unprivileged:alpine
COPY website/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /repo/website/public/ /usr/share/nginx/html/
EXPOSE 8080
