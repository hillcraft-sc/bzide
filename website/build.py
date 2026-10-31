#!/usr/bin/env python3
"""Builds Bzide's website into website/public: Home, Support (from
docs/USER-GUIDE.md), Privacy (from docs/PRIVACY.md) and Accessibility (from
docs/ACCESSIBILITY.md), so the site, the app
(Settings > Help and Privacy) and the repo always say the same thing.

Only the Python standard library. Run from anywhere:
    python3 website/build.py
The Markdown handled is what those docs use (as MarkdownBlocks.swift in the
app): # headings, paragraphs, - bullets, 1. steps, | tables, and inline
**bold**, *italic*, `code` and [links](url).
"""

import html
import re
import shutil
from pathlib import Path

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
OUT = WEBSITE / "public"

# The one place to change the site's details.
SITE = {
    "name": "Bzide",
    "url": "https://bzide.hillcraft-sc.com",
    # The dedicated support address (public on the Support page).
    "support_email": "bzide-admin@hillcraft-sc.com",
    # The App Store link (empty hides the button and shows "Coming soon").
    "app_store_url": "https://apps.apple.com/app/bzide/id6825602899",
    # The tip page (Ko-fi), linked from Support, Home and the footer.
    "tip_url": "https://ko-fi.com/hillcraftsc",
}


# MARK: - Markdown

def inline(text: str) -> str:
    """Escapes HTML, then styles code, links, bold and italic."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", text)
    return text


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"[`*]", "", text.lower())).strip("-")


def cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def markdown(source: str) -> tuple[str, str, list[tuple[str, str]]]:
    """The page's title (its # heading), its HTML, and its ## sections for a contents list."""
    title, parts, sections = "", [], []
    paragraph, bullets, steps, table = [], [], [], []

    def flush():
        nonlocal paragraph, bullets, steps, table
        if paragraph:
            parts.append(f"<p>{inline(' '.join(paragraph))}</p>")
        if bullets:
            parts.append("<ul>" + "".join(f"<li>{inline(item)}</li>" for item in bullets) + "</ul>")
        if steps:
            parts.append("<ol>" + "".join(f"<li>{inline(item)}</li>" for item in steps) + "</ol>")
        if table:
            header, rows = table[0], [row for row in table[1:] if not all(re.fullmatch(r":?-+:?", c) for c in row)]
            head = "".join(f"<th>{inline(c)}</th>" for c in header)
            body = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>" for row in rows)
            parts.append(f'<div class="table"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>')
        paragraph, bullets, steps, table = [], [], [], []

    for raw in source.replace("\r\n", "\n").split("\n"):
        line = raw.strip()
        heading = re.match(r"^(#{1,3}) (.+)$", line)
        step = re.match(r"^(\d{1,3})\. (.+)$", line)
        if not line:
            flush()
        elif heading:
            flush()
            level, text = len(heading.group(1)), heading.group(2).strip()
            if level == 1:
                title = text
                continue
            anchor = slug(text)
            if level == 2:
                sections.append((anchor, text))
            parts.append(f'<h{level} id="{anchor}">{inline(text)}</h{level}>')
        elif line.startswith(("- ", "* ")):
            if paragraph or steps or table:
                flush()
            bullets.append(line[2:])
        elif step:
            if paragraph or bullets or table:
                flush()
            steps.append(step.group(2))
        elif line.startswith("|"):
            if paragraph or bullets or steps:
                flush()
            table.append(cells(line))
        elif bullets:
            bullets[-1] += " " + line
        elif steps:
            steps[-1] += " " + line
        else:
            if table:
                flush()
            paragraph.append(line)
    flush()
    return title, "\n".join(parts), sections


def tip_link(text: str) -> str:
    return f'<a href="{SITE["tip_url"]}">{text}</a>'


def email_link() -> str:
    """The support address as a mailto link. Cloudflare's Email Address
    Obfuscation would swap it for a link to its own page and a script to
    decode it, which the site's Content-Security-Policy blocks, so it's marked
    for Cloudflare to leave alone."""
    address = SITE["support_email"]
    return f'<!--email_off--><a href="mailto:{address}">{address}</a><!--/email_off-->'


# MARK: - Pages

def page(slug_name: str, title: str, body: str, description: str) -> str:
    nav = "".join(
        f'<a href="{href}"{" aria-current=\"page\"" if key == slug_name else ""}>{label}</a>'
        for key, href, label in (("home", "/", "Home"), ("support", "/support.html", "Support"), ("privacy", "/privacy.html", "Privacy"), ("accessibility", "/accessibility.html", "Accessibility"))
    )
    full_title = SITE["name"] if slug_name == "home" else f"{title} · {SITE['name']}"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(full_title)}</title>
<meta name="description" content="{html.escape(description)}">
<link rel="icon" href="/favicon.png">
<link rel="stylesheet" href="/style.css">
</head>
<body>
<header class="site">
  <a class="brand" href="/"><img src="/icon-256.png" alt="" width="32" height="32">{SITE['name']}</a>
  <nav>{nav}</nav>
</header>
<main>
{body}
</main>
<footer class="site">
  <p>Bzide is an independent app for Navidrome and other Subsonic-compatible servers. It is not affiliated with or endorsed by the Navidrome or Subsonic projects.</p>
  <p>Made by <a href="https://hillcraft-sc.com">Hillcraft</a> · <a href="/support.html">Support</a> · <a href="/privacy.html">Privacy</a> · <a href="/accessibility.html">Accessibility</a> · {tip_link("Leave a tip")} · {email_link()}</p>
</footer>
</body>
</html>
"""


def document_page(slug_name: str, source: Path, intro: str, description: str) -> str:
    title, body, sections = markdown(source.read_text(encoding="utf-8"))
    contents = "".join(f'<li><a href="#{anchor}">{inline(text)}</a></li>' for anchor, text in sections)
    toc = f'<nav class="toc" aria-label="Contents"><h2>Contents</h2><ol>{contents}</ol></nav>' if len(sections) > 3 else ""
    return page(slug_name, title, f'<article class="doc"><h1>{inline(title)}</h1>{intro}{toc}{body}</article>', description)


def home() -> str:
    app_store = (
        f'<a class="button" href="{SITE["app_store_url"]}">Download on the App Store</a>'
        if SITE["app_store_url"] else '<p class="soon">Coming soon to the App Store.</p>'
    )
    features = [
        ("Your library, beautifully played", "Artists, albums, playlists, genres and favorites; gapless playback; a queue you control; Random Mix, Mix My Cuts and endless Spin Off."),
        ("Listen anywhere", "Download albums, playlists and songs for offline listening. Downloaded playlists stay up to date, and you choose the streaming quality for Wi-Fi and cellular."),
        ("Lyrics", "Synced lyrics that light up word by word. Tap a line to jump there; fix timing that runs early or late."),
        ("Internet radio", "Your server's stations, thousands more to discover, and Spin the Dial for something new that fits your taste."),
        ("Make it yours", "Catppuccin, Gruvbox, Nord, Dracula and Tokyo Night themes, a 10-band equalizer, and eleven visualizers."),
        ("Everywhere on your iPhone", "CarPlay, Home Screen widgets in your theme, a Favorite Song button for the Lock Screen, and Siri."),
        ("Built for privacy", "Your music and listening go only to your own server. No ads, no tracking, no accounts, no third-party code. Every outside service is off until you turn it on."),
        ("Accessible", "VoiceOver and Voice Control throughout, Larger Text, Reduce Motion and Increase Contrast."),
    ]
    cards = "".join(f'<div class="card"><h3>{html.escape(t)}</h3><p>{html.escape(d)}</p></div>' for t, d in features)
    body = f"""<section class="hero">
  <img class="icon" src="/icon-256.png" alt="The Bzide app icon" width="128" height="128">
  <h1>Your music, your server, no snooping.</h1>
  <p class="lede">Bzide is a fast, private music player for iPhone that plays the music on your own Navidrome or Subsonic server.</p>
  {app_store}
</section>
<section class="needs">
  <h2>What you need</h2>
  <p>A <a href="https://www.navidrome.org">Navidrome</a> or other Subsonic-compatible server with your music on it, and an iPhone with iOS 27. Bzide doesn't include any music or streaming service: it plays yours.</p>
</section>
<section class="features">{cards}</section>
<section class="more">
  <p>New to Bzide? The <a href="/support.html">user guide</a> walks through everything. Wondering what goes where? See <a href="/privacy.html">privacy</a>.</p>
  <p>Bzide is free. If you enjoy it, you can {tip_link("leave a tip on Ko-fi")}.</p>
</section>"""
    return page("home", "Home", body, "Bzide: a fast, private iPhone music player for your own Navidrome or Subsonic server.")


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for file in (WEBSITE / "static").iterdir():
        shutil.copy(file, OUT / file.name)
    shutil.copy(WEBSITE / "style.css", OUT / "style.css")
    contact = (
        f'<div class="contact"><h2>Contact</h2><p>Questions, problems or ideas? Email '
        f'{email_link()}. '
        "It helps to include your iPhone model and iOS version (iPhone Settings > General > About), and what you were doing when it happened.</p></div>"
        '<div class="contact"><h2>Tip jar</h2><p>Bzide is free, with no ads or subscriptions. '
        f'If it\'s made your listening better and you want to say thanks, you can {tip_link("leave a tip on Ko-fi")}. '
        "Tips are entirely optional and unlock nothing. Thank you!</p></div>"
    )
    pages = {
        "index.html": home(),
        "support.html": document_page("support", REPO / "docs" / "USER-GUIDE.md", contact, "How to use Bzide, and how to get help."),
        "privacy.html": document_page("privacy", REPO / "docs" / "PRIVACY.md", "", "Bzide's privacy policy: what it sends, to whom, and what it keeps on your iPhone."),
        "accessibility.html": document_page("accessibility", REPO / "docs" / "ACCESSIBILITY.md", "", "How Bzide works with VoiceOver, Voice Control, Larger Text, Reduce Motion and other iOS accessibility features."),
    }
    for name, content in pages.items():
        (OUT / name).write_text(content, encoding="utf-8")
    print(f"Built {len(pages)} pages into {OUT}")


if __name__ == "__main__":
    build()
