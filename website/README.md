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

The site is now on port 8086. In cloudflared's config, add an ingress rule above the catch-all:

```yaml
ingress:
  - hostname: bzide.hillcraft-sc.com
    service: http://localhost:8086
  # ...existing rules...
  - service: http_status:404
```

Then run `cloudflared tunnel route dns <tunnel name> bzide.hillcraft-sc.com` and restart cloudflared. If you manage the tunnel in the Cloudflare dashboard (Zero Trust > Networks > Tunnels > Public Hostname), add the hostname there instead. The site only listens on the server itself (127.0.0.1), so it can't be reached from the LAN around the tunnel. If cloudflared runs in its own container, `localhost` won't reach it: put both containers on one Docker network and use `http://bzide-website:8080` instead.

To update after the docs change: `git pull && docker compose up -d --build`.
