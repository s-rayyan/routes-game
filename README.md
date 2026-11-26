# Routes

A calm city-traffic puzzle for your phone, inspired by Mini Motorways. Draw roads from houses to the building of the same colour and keep the city moving.

**Play:** https://s-rayyan.github.io/routes-game/

- Five cities to unlock, a daily map that is the same for everyone, and an endless mode that keeps growing.
- Motorways, bridges that bend and cross, roundabouts, traffic lights, diagonal driveways.
- Challenge links: after a daily map, tap **Challenge friends**. They play the exact same map with your score to beat.
- Global leaderboards (all-time and today's daily map), levels, undo, pause-and-build.
- A shop: trade road tiles for roundabouts, traffic lights, motorways and bridges.

Everything is one file, `index.html`. No build step.

## Leaderboard setup (Supabase)

The leaderboard runs on a free Supabase project. The game talks to it straight from the browser, so there's no server to run. Players only pick a nickname. Each device keeps a random secret, so nobody can change anyone else's score.

1. Create a free project at [supabase.com](https://supabase.com).
2. **SQL Editor → New query:** paste in [`supabase.sql`](supabase.sql) and press **Run**.
3. **Project Settings → API:** copy the **Project URL** and the **anon / publishable key**. Both are meant to be public.
4. In `index.html`, set `SB_URL` and `SB_KEY` to those two values and push.

Until step 4 is done, the game works normally and the leaderboard says it isn't switched on yet.

The SQL keeps the tables locked. The browser can only call three functions: post your score, post your daily score, and read the board. Scores only ever go up. Names are limited to 2–16 letters, numbers, spaces and `- _ .`. Daily scores are only accepted for today's map. These checks were tested against a real Postgres database.

## Hosting

GitHub Pages: **Settings → Pages → Build and deployment → Deploy from a branch → `main` / `(root)`**.
