# Navidrome app catalog entry

Bzide's entry for the list of apps at [navidrome.org/apps](https://www.navidrome.org/apps/) (Gitea #23), ready for a pull request to [navidrome/website](https://github.com/navidrome/website). Their guide: [Adding apps](https://www.navidrome.org/docs/developers/adding-apps/).

**Open source:** with a `repoUrl`, the catalog treats an entry as open source and requires the repo to have at least 15 stars (the validator fails below that). Bzide's repo (github.com/hillcraft-sc/bzide) is public but doesn't have them yet, so the entry has no `repoUrl` (it's commented out in `bzide/index.yaml`) and is accepted as a store-listed app (navidrome/website PR #541). Once the repo has 15 stars, add the `repoUrl` line in a small follow-up pull request to get the open source badge. Don't use `isOpenSource: false` for this: it says the source isn't public. Its images (`thumbnail.webp`, `screen1.webp` to `screen4.webp`) are in this folder.

**When:** now; Bzide is on the App Store and `bzide/index.yaml` has its link. A closed-source app is only accepted once it's publicly available in a store (open-source ones need a public repo with 15 stars instead).

**Steps:**

1. Add the screenshots to `bzide/`, made from the App Store ones: `thumbnail.webp` (the one on the catalog card; a screenshot, not the icon, square preferred) and `screen1.webp` to `screen4.webp` (up to 5). WebP, at most 1200 pixels on a side, each under 500 KB. For example: `sips -Z 1200 shot.png --out shot-small.png && cwebp -q 80 shot-small.png -o screen1.webp`.
2. Fork navidrome/website on GitHub, copy `bzide/` to `assets/apps/bzide/`, then run `npm install`, `npm run validate:app bzide`, and open the pull request.

The description is at most 500 characters and 1-2 sentences; keywords at most 6 (searched, not shown).
