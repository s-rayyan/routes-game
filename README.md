# Routes

A calm city-traffic puzzle for your phone, inspired by Mini Motorways. Draw roads from houses to the building of the same colour and keep the city moving.

**Play:** https://s-rayyan.github.io/routes-game/

- Five cities to unlock, a daily map that is the same for everyone, and an endless mode that keeps growing.
- Motorways, bridges that bend and cross, roundabouts, traffic lights, diagonal driveways.
- Challenge links: after a daily map, tap **Challenge friends**. They play the exact same map with your score to beat.
- Global leaderboards (all-time and today's daily map), achievements, levels, undo, pause-and-build.

Everything is one file, `index.html`. No build step.

## Leaderboard setup (Firebase)

The leaderboard uses the `gamehub-7b1e2` Firebase project. Each device signs in anonymously, so players only pick a nickname. One-time setup:

1. **Firebase console → Authentication → Sign-in method → Anonymous → Enable.**
2. **Authentication → Settings → Authorized domains → Add `s-rayyan.github.io`.**
3. **Firestore → Rules:** replace the rules with [`firestore.rules`](firestore.rules) from this repo and **Publish**. It keeps the Game Hub's existing `users/{uid}` rules exactly as they are and adds two read-only-to-the-world, write-your-own-entry collections: `routes_players` and `routes_daily/{date}/scores`. Scores can only go up, names are limited to letters, numbers, spaces and `- _ .`, and entries can't be deleted from the client. (Also copy the file into the `game-hub` repo if you deploy rules from there with `firebase deploy --only firestore:rules`, so the two don't drift.)

The rules were tested against the Firestore emulator: players can only write their own entry, scores can't decrease, junk values and markup in names are rejected, and the hub's saves stay private.

## Hosting

GitHub Pages: **Settings → Pages → Build and deployment → Deploy from a branch → `main` / `(root)`**.
