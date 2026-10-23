# Bzide website

bzide.hillcraft-sc.com: Home, Support (the user guide plus the contact email) and Privacy. The Support and Privacy pages are built from `docs/USER-GUIDE.md` and `docs/PRIVACY.md`, the same files the app shows in Settings > Help and Privacy, so the three never disagree. Edit the docs, not the HTML.

- `build.py`: builds `public/` (git-ignored) using only the Python standard library. The support email and the App Store link are set in `SITE` at the top.
- `style.css`, `static/`: the stylesheet, the icon and the favicon.
- `Dockerfile`, `nginx.conf`, `docker-compose.yml`: build the pages and serve them with nginx, with no access log.

## Preview

```
python3 website/build.py
python3 -m http.server 8765 --directory website/public
```

Then open http://127.0.0.1:8765.

## Deploy

On the server, as a dedicated user, check out only the folders the site needs, using a read-only deploy key:

```
git clone --filter=blob:none --sparse <repo SSH address> /srv/bzide-website
cd /srv/bzide-website
git sparse-checkout set docs website
cd website
docker compose up -d --build
```

The site has no published port. It joins `tunnel`, the Docker network the `cloudflared` container is on (an external network in `docker-compose.yml`), so only the tunnel can reach it. In the tunnel's Public Hostname (Cloudflare dashboard, Zero Trust > Networks > Tunnels), map `bzide.hillcraft-sc.com` to `http://bzide-website:8080`.

To check it from the server (the cloudflared image has no shell tools):

```
docker run --rm --network tunnel busybox wget -qO- http://bzide-website:8080 | head -3
```

To update after the docs change: `git pull && docker compose up -d --build`.
