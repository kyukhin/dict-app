# Website

> Spec written by Claude (AI) for LibreDict.
> Status: Approved by Kirill on 2026-11-09 · Epic: #194 · Tickets: #29 · Updated: 2026-11-09

## Why

LibreDict has no website. The App Store Support URL is a Telegram link, the privacy policy has no home, and there is nothing to share outside the App Store. App Store Connect needs a Support URL and a Privacy Policy URL when 2.0.0 is submitted (2026-11-20). Kirill, 2026-11-09: a first version of the site goes live with 2.0.0.

## Behaviour

### Pages and languages

- Address: `https://libredict.app`; `www.libredict.app` redirects to it.
- Five languages, each with three pages:

| Language | Home | Privacy | Support |
|---|---|---|---|
| English | `/` | `/privacy.html` | `/support.html` |
| Russian | `/ru/` | `/ru/privacy.html` | `/ru/support.html` |
| Spanish | `/es/` | `/es/privacy.html` | `/es/support.html` |
| Arabic (right to left) | `/ar/` | `/ar/privacy.html` | `/ar/support.html` |
| Greek | `/el/` | `/el/privacy.html` | `/el/support.html` |

- Every page links the same page in the other four languages, each named in its own language (English, Русский, Español, العربية, Ελληνικά). No redirect by browser language: the root is English.
- The header has the name and the language links; the footer has Privacy, Support, GitHub and "LibreDict is open source (MIT)".

### Home

- The name, one line on what it is, and Apple's "Download on the App Store" badge in the page's language, linking to `https://apps.apple.com/app/id6763217128`.
- Four short blocks, from the 2.0 App Store description (`metadata/*.md`):
  - Dictionary: English included, other languages download once and then work offline; search by any inflected form (έγραψα finds γράφω); declension and conjugation tables.
  - Learn: word lists by level (Greek A1–B1, English A1–C2) or your own (CSV, Anki, Quizlet); daily practice with spaced repetition and real example sentences.
  - Grammar: a conjugation drill and short grammar topics, Greek first. Named as features of the app, not as a Greek app (Kirill, 2026-11-09): only Greek has them so far.
  - Privacy: no ads, no accounts, no tracking; everything stays on the device.
- Five 2.0 screenshots in the page's language: the Learn tab, an exercise, the conjugation drill, a word with its table, a grammar topic.

### Privacy policy

Plain facts, one short section each, with a "Last updated" date:
- The app collects no data: no analytics, no ads, no accounts, no identifiers. History, My words, learning progress and statistics stay on the device.
- Language downloads: the app downloads public files from GitHub Releases when the user asks. As for any download, GitHub receives the IP address and the system user agent, under GitHub's privacy statement (linked). Nothing identifies the user to LibreDict.
- Report a bug: only when the user taps it; the Mail app shows the whole message, with the app and iOS versions, before it is sent.
- The daily reminder is a local notification; nothing goes to a server.
- The website itself sets no cookies, loads nothing from other servers and counts no visits.
- Contact: the support address.

### Support

- Email `support@libredict.app` (Cloudflare Email Routing forwards it to Kirill) and Telegram `https://t.me/kyukhin`, Kirill's own account (Kirill, 2026-11-09). Report a bug in the app: Settings → Support.
- A short FAQ: languages download once, then work offline; where the 1.x bookmarks are (My words in Learn, once a language is chosen; the same words as #288's welcome text); how to download or remove a language (Settings → Dictionaries → Languages).

## Design

- **Files**: `site/` in this repository (Kirill, 2026-11-09). `Scripts/build_site.py` (Python standard library only) renders the 15 pages from one HTML template and the texts of each language, so the five languages cannot drift apart; its output in `site/` is committed and served as is.
- **Page**: HTML5 and one stylesheet (`site/assets/style.css`), the system font stack, light and dark (`prefers-color-scheme`), one column on a phone, two up to 960 px. No JavaScript, no web fonts, no CDN, no analytics: every file comes from `libredict.app`. Arabic pages have `lang="ar" dir="rtl"`; each page has `hreflang` alternates for the other four.
- **Images**: Apple's official badge SVGs, unmodified, black, one per language (Apple Marketing Tools); the app icon as favicon; screenshots as PNG under 300 KB each, with `width` and `height` set.
- **Screenshots**: iPhone 17, iOS 26.4, status bar fixed to 9:41 with `simctl status_bar override`, real-looking data (no test fixtures), one set per language. Kirill's App Store mockups (#183) can replace them later.
- **Deploy**: `.github/workflows/pages.yml` runs on a push to master that touches `site/**` (and by hand): `actions/upload-pages-artifact` with `site/`, then `actions/deploy-pages`. Repository Settings → Pages: source GitHub Actions, custom domain `libredict.app`, Enforce HTTPS (`.app` is HTTPS only).
- **DNS** (Kirill, in the Cloudflare zone of `libredict.app`; nameservers moved there on 2026-05-26):
  - replace the apex A and AAAA records with GitHub Pages: A `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`; AAAA `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153`;
  - CNAME `www` → `kyukhin.github.io`;
  - all "DNS only" (grey cloud), so GitHub can issue the certificate;
  - keep the MX and TXT records: Cloudflare Email Routing forwards `support@libredict.app`;
  - verify the domain for GitHub Pages in the GitHub account settings (a TXT record), so no other account can claim it.
- **App Store Connect** (Kirill, at submission, every localization): Support URL `https://libredict.app/<lang>/support.html`, Privacy Policy URL `https://libredict.app/<lang>/privacy.html`, Marketing URL `https://libredict.app/<lang>/` (English without `<lang>/`).
- The app does not change.

## Test plan

| Acceptance criterion | Test |
|---|---|
| #29: five languages, each with home, privacy and support | `Scripts/build_site.py --check`: every page exists in each language; every internal link and image resolves; each page links its four siblings and has their `hreflang`; Arabic pages have `dir="rtl"` |
| #29: no analytics, cookies or trackers | `--check`: no `<script>`, `<iframe>` or external `src`/`href` other than apps.apple.com, github.com, docs.github.com, t.me and `mailto:`; after deploy, no `Set-Cookie` header (`curl -I`) |
| #29: works on phone and desktop | QA: every page at 390 px and 1280 px wide, light and dark, in each language, screenshots attached to the PR; Arabic reads right to left |
| #29: the site is live | after DNS: `https://libredict.app` and a page per language answer 200 with a valid certificate; `http://` and `www` redirect |
| #29: App Store Connect points to it | Kirill sets the three URLs; QA opens each of them |

## Open questions

None.

## History

- 2026-11-09: First draft. Kirill: the site lives in `site/` and deploys with GitHub Actions; 2.0 screenshots from the start; support by email and Telegram; the drill and grammar are the app's features, with Greek as the first language, not a "Greek" block.
- 2026-11-09: Approved by Kirill ("давай делать тестовую версию сайта"). Open question 2 defaulted to `support@libredict.app`; the Telegram link waits for Kirill.
- 2026-11-09: Support shows `support@libredict.app` and Telegram `t.me/kyukhin` (Kirill).
