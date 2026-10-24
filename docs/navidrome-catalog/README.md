# Navidrome app catalog entry

Bzide's entry for the list of apps at [navidrome.org/apps](https://www.navidrome.org/apps/) (Gitea #23), ready for a pull request to [navidrome/website](https://github.com/navidrome/website). Their guide: [Adding apps](https://www.navidrome.org/docs/developers/adding-apps/).

**When:** after Bzide is on the App Store. A closed-source app is only accepted once it's publicly available in a store (open-source ones need a public repo with 15 stars instead).

**Steps:**

1. In `bzide/index.yaml`, replace the `idTODO` link with the App Store link.
2. Add the screenshots to `bzide/`, made from the App Store ones: `thumbnail.webp` (the one on the catalog card; a screenshot, not the icon, square preferred) and `screen1.webp` to `screen4.webp` (up to 5). WebP, at most 1200 pixels on a side, each under 500 KB. For example: `sips -Z 1200 shot.png --out shot-small.png && cwebp -q 80 shot-small.png -o screen1.webp`.
3. Fork navidrome/website on GitHub, copy `bzide/` to `assets/apps/bzide/`, then run `npm install`, `npm run validate:app bzide`, and open the pull request.

The description is at most 500 characters and 1-2 sentences; keywords at most 6 (searched, not shown).
