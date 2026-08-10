#!/bin/zsh
# How many people have downloaded the app.
#
# GitHub counts every release asset download, so this is real installs rather
# than button clicks — and it needs no analytics, no tracking script, and
# nothing added to the website.
#
# `iPodConnect.zip` is the stable-named asset the website's Download button
# points at, so that column is effectively the site's conversion. The
# versioned files are what Sparkle fetches for auto-updates.
set -e
REPO="${GITHUB_REPO:-Davidjrsomper/ipod-connect}"

gh api "repos/$REPO/releases" --paginate | python3 -c "
import sys, json
rels = json.load(sys.stdin)
site = updates = total = 0
rows = []
for r in sorted(rels, key=lambda x: x['published_at']):
    for a in r['assets']:
        c = a['download_count']
        total += c
        if a['name'] == 'iPodConnect.zip': site += c
        elif a['name'].endswith('.zip'):   updates += c
        if c: rows.append((r['tag_name'], r['published_at'][:10], a['name'], c))

print(f'{\"release\":<10} {\"date\":<12} {\"asset\":<28} {\"downloads\":>9}')
print('-' * 62)
for t, d, n, c in rows:
    print(f'{t:<10} {d:<12} {n:<28} {c:>9}')
print('-' * 62)
print(f'From the website (iPodConnect.zip){site:>28}')
print(f'Auto-updates (versioned files){updates:>32}')
print(f'TOTAL{total:>57}')
"
