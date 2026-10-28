# Bzide website

bzide.hillcraft-sc.com: Home, Support (the user guide plus the contact email and tip jar), Privacy and Accessibility (the App Store's Accessibility URL). Support, Privacy and Accessibility are built from `docs/USER-GUIDE.md`, `docs/PRIVACY.md` and `docs/ACCESSIBILITY.md`; the first two are also what the app shows in Settings > Help and Privacy, so they never disagree. Edit the docs, not the HTML.

- `build.py`: builds `public/` (git-ignored) using only the Python standard library. The support email, the App Store link and the tip page (Ko-fi) are set in `SITE` at the top.
- `style.css`, `static/`: the stylesheet, the icon and the favicon.
- `Dockerfile`, `nginx.conf`, `docker-compose.yml`: build the pages and serve them with nginx, with no access log.

## Preview

```
python3 website/build.py
python3 -m http.server 8765 --directory website/public
```

Then open http://127.0.0.1:8765.

## Deploy

On the server, as a dedicated user (`bzide-web`), check out only the folders the site needs. Forgejo's SSH isn't reachable through the Cloudflare Tunnel, so the checkout uses HTTPS with a Forgejo access token that can only read repositories (Settings > Applications), saved for that user by git's `store` helper (`~/.git-credentials`, readable only by them). Revoke it in Forgejo to cut off access.

```
sudo -u bzide-web git config --global credential.helper store
sudo -u bzide-web git clone --filter=blob:none --sparse https://git.hillcraft-sc.com/eric/MusicApp.git /srv/bzide-website
cd /srv/bzide-website
sudo -u bzide-web git sparse-checkout set docs website
cd website
docker compose up -d --build
```

The first clone or pull asks for a username and password: enter the Forgejo username and the token.

The site has no published port. It joins `tunnel`, the Docker network the `cloudflared` container is on (an external network in `docker-compose.yml`), so only the tunnel can reach it. In the tunnel's Public Hostname (Cloudflare dashboard, Zero Trust > Networks > Tunnels), map `bzide.hillcraft-sc.com` to `http://bzide-website:8080`.

To check it from the server (the cloudflared image has no shell tools):

```
docker run --rm --network tunnel busybox wget -qO- http://bzide-website:8080 | head -3
```

To update after the docs change, from `/srv/bzide-website/website`: `sudo -u bzide-web git pull && docker compose up -d --build` (with `sudo` before `docker` if needed). The pull runs as `bzide-web` because git refuses a checkout owned by another user.
