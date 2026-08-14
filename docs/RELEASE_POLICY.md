# When to cut a release

Every release interrupts every user, so releasing isn't free.

Early on this project published **13 releases in two days**, and because
`SUAutomaticallyUpdate` wasn't set, each one raised a modal. Anyone who
installed on day one was interrupted thirteen times. Both halves of that are
now fixed.

## Commits are free, releases are not

Commit whenever. Push whenever. Neither reaches a user.

A release happens only when you push a version tag:

```bash
git tag v1.7.0
git push origin v1.7.0
```

That triggers `.github/workflows/release.yml`, which builds, signs, updates
the appcast and publishes, the same steps `scripts/release.sh` does locally,
but reproducibly and only when you asked for it.

## What earns a release

- A fix for something that's actually broken for users
- A feature people can use
- Anything affecting data safety: formatting, the bootloader, syncing

## What doesn't

- Refactors, comments, docs
- Website changes (GitHub Pages publishes those on push, no app release needed)
- Work in progress

Batch small changes. Three fixes in one release beats three releases.

## Updates are silent now

`SUAutomaticallyUpdate` is on, so Sparkle downloads in the background and
applies on the next launch. No dialog for routine releases.

Users can still check manually (**iPod Connect → Check for Updates…**), and
can turn automatic updates off in Sparkle's own prompt on first run.

## CI setup, one time

The workflow needs the Sparkle signing key as a repository secret named
`SPARKLE_PRIVATE_KEY`. Export it from the Keychain:

1. Open **Keychain Access**
2. Find **"Private key for signing Sparkle updates"**
3. Right-click → Export, save as a `.p8`/text file
4. Repo → Settings → Secrets and variables → Actions → **New repository secret**
5. Name `SPARKLE_PRIVATE_KEY`, paste the key's contents

Without that secret the workflow fails at the signing step, and updates would
be rejected by installed copies, which is the correct failure. Never commit
the key.
