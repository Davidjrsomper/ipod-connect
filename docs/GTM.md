# iPod Connect — Go-to-Market

## Positioning

**One-liner:** The Mac music player for people who kept their FLAC
library — and miss when music felt like something you owned.

**The wedge:** Apple Music is a rental service with a search box. Anyone
with a real local library — ripped CDs, Bandcamp purchases, Soulseek
hauls, hi-res downloads — is a second-class citizen in the modern Music
app. Meanwhile macOS *still* has no first-party FLAC support, so the
single most common lossless format is invisible to Apple's own player.

iPod Connect is a native Mac app that plays FLAC properly, shows your
whole library the way iTunes used to, and turns into a working iPod
classic when you want it to.

**Why now:** the iPod revival is real and it is young. Refurb iPod prices
have climbed for years, iPod modding (flash storage, larger batteries)
is a healthy hobbyist scene, and "digital ownership" as a reaction to
streaming rot — songs silently vanishing from playlists, albums getting
re-mastered under you — has moved from niche to mainstream discourse.
The people rediscovering iPods are not nostalgic Gen X; they are
teenagers and 20-somethings buying a 2007 device for the first time.

## Target audience

**Primary — "library keepers" (highest intent)**
People with 500+ local files who already resent the modern Music app.
They rip CDs, buy Bandcamp, care about tags, and know what FLAC is.
Small, but they convert immediately and evangelize.

**Secondary — "iPod revivalists" (highest growth)**
The r/ipod, TikTok, and YouTube-modding crowd. They own a physical iPod
or want to. The iPod emulator view is the hook; the library manager is
what makes them stay.

**Tertiary — "anti-streaming" converts**
People leaving Spotify over artist payouts, AI slop tracks, or losing
saved albums. They have a folder of downloads and no good player.

**Explicitly not targeting:** casual listeners happy with streaming.
They will not clear the Gatekeeper warning, and nothing about this
product is for them.

## Distribution channels, in priority order

### 1. Reddit (the actual launch)
- **r/ipod** (~200k) — the emulator view is the post. Lead with a screen
  recording of the click wheel scrolling a real library.
- **r/audiophile, r/headphones** — lead with FLAC support and gapless
  playback, never with nostalgia. This crowd is allergic to gimmicks.
- **r/macapps** — lead with "native SwiftUI, no Electron, 2MB."
- **r/DataHoarder** — lead with "points at your existing folder, doesn't
  move or rename anything."

Post as a person, not a brand. Reddit punishes marketing voice hard.
"I built this because I got a refurb Classic and couldn't stand Music
.app" is the honest framing and also the effective one.

### 2. Hacker News — "Show HN"
One shot; make it count. HN responds to the *technical* story, not the
nostalgia: **"Show HN: I wrote a FLAC parser and an iPod click wheel in
SwiftUI."** The native-FLAC-metadata-parsing angle (no libFLAC, no
ffmpeg, reads STREAMINFO/VORBIS_COMMENT directly) is genuinely
interesting to that audience. Post Tue–Thu, 8–10am ET. Be in the thread
all day answering.

### 3. YouTube / TikTok creator seeding
The iPod modding scene is video-native. Identify 10–20 creators making
iPod restoration or "why I quit Spotify" content and send a personal
note with a download link and a 30-second demo clip. One mid-size
creator demoing the click wheel is worth more than every other channel
combined.

### 4. Mac software press
MacStories, Six Colors, Daring Fireball, and the "Mac apps of the week"
newsletters (e.g. Mac Power Users). These reward *taste*. Pitch the
craft: hand-matched iTunes 10 colors, real 4:3 iPod proportions, dynamic
dark mode built to Apple's HIG.

### 5. Bandcamp-adjacent communities
Bandcamp buyers download FLAC and immediately need somewhere to put it.
This is the highest-intent, least-served audience on the list.

## Launch sequence

**Pre-launch (before any post)**
- [ ] Verify `SUFeedURL` + `SUPublicEDKey` are final and correct — these
      cannot be changed for anyone who already downloaded
- [ ] Publish v1.0.0 and confirm a 1.0.0 → 1.0.1 update actually installs
      on a *second* Mac, not just the build machine
- [ ] Landing page: screenshots, 30s demo video, honest install
      instructions including the Gatekeeper steps
- [ ] Decide the licensing/pricing story (see below)

**Week 1** — Reddit posts, staggered a few days apart, different angle
per subreddit. Respond to every comment.

**Week 2** — Show HN, once Reddit feedback has smoothed the obvious
rough edges. Nothing kills an HN launch like a bug found in the first
ten minutes.

**Weeks 3–4** — Creator outreach with the social proof from weeks 1–2.

**Ongoing** — Ship visible updates fast. The auto-updater is a retention
feature: every install that receives a polished update becomes a person
who trusts the project.

## Metrics that matter

- **Download → first launch** — measures how many people the Gatekeeper
  warning kills. If this is under ~50%, fixing signing beats every
  marketing activity.
- **Folder chosen** — the real activation event. A user who never picks
  a folder never saw the product.
- **Update adoption rate** — the honest measure of whether people kept it
  installed.

There is no telemetry in the app today, and adding it to a
privacy-conscious local-music audience would be poorly received. Prefer
download counts (GitHub Releases API), appcast fetch counts from server
logs, and direct user feedback.

## Pricing

**Recommended: free and open source now, paid later if it earns it.**

The realistic paid options all have problems today: the Mac App Store
would reject the iPod trade dress; paid-direct requires the Developer ID
you don't yet have; and an unsigned paid app is a support nightmare.

Free-and-open removes friction while the audience is being built, makes
the Reddit/HN launches dramatically easier (both communities are hostile
to closed paid tools from unknown developers), and lets contributors fix
the gaps. If it gains traction, the proven paths are a paid "Pro" tier
(library sync, real device sync, advanced tagging), or GitHub Sponsors.

## The risks worth naming

1. **Trademark.** "iPod" is an Apple trademark, and the interface is a
   deliberate recreation of Apple's iTunes 10 and iPod classic trade
   dress. Marketing this publicly under this name is the highest-risk
   decision in this document. The most likely outcome is a takedown
   demand rather than litigation, but a takedown after launch means
   losing the name, the domain, the repo URL, and the audience's ability
   to find you. **Talk to an IP lawyer before spending money on this
   launch.** A contingency name and domain, secured in advance, costs
   almost nothing and preserves everything if a letter arrives.

2. **The Gatekeeper wall.** Unsigned means a scary warning and manual
   approval. Expect to lose a large share of non-technical downloaders.
   The $99 Developer Program is the single highest-ROI spend available.

3. **Apple Silicon only.** Intel Mac owners — heavily represented among
   people running older hardware and keeping local libraries — cannot run
   it today. See `DISTRIBUTION.md`.

4. **The gimmick trap.** The iPod view drives the virality; the library
   manager drives retention. If the desktop experience is not genuinely
   good, iPod Connect gets one viral week and then nothing.

## Feature roadmap (GTM-driven)

**Before launch**
- Universal binary — do not exclude Intel users at the moment of peak
  attention
- Gapless playback — table stakes for the audiophile segment
- Fix any tagging gaps found in real libraries

**Fast follows (weeks 1–8)**
- Playlists, including .m3u import
- Cover Flow — the single most-requested nostalgic feature, and a strong
  second viral moment
- Smart playlists

**Later, differentiating**
- Actual iPod sync over USB — the feature nobody else offers, and the one
  that makes the name make sense. Also the feature most likely to draw
  Apple's attention.
- Last.fm scrobbling — deeply loved by this exact audience
- ReplayGain support
