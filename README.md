# Routes

A calm city-traffic puzzle for your phone, inspired by Mini Motorways. Draw roads from houses to the building of the same colour and keep the city moving.

**Play:** https://routes-game.onrender.com/

- Five cities to unlock, a daily map that is the same for everyone, and an endless mode that keeps growing.
- Motorways, bridges that bend and cross, roundabouts, traffic lights, diagonal driveways.
- Challenge links: after a daily map, tap **Challenge friends**. They play the exact same map with your score to beat.
- Builder mode: endless, with Mini Motorways-style materials (a weekly upgrade choice and the shop). New homes, shops and colours only arrive while your town runs smoothly: homes connected, every shop reachable, no shop maxed out and traffic flowing. While it's paused no new orders pile up, so a shop can catch up. A tag at the top says what's holding it back. Stores sit in small groups on paved plazas, and homes form named neighbourhoods, outlined on the map, with wide gaps between. Builder scores stay off the leaderboard.
- Shops level up as they serve customers (after 15, 40 and 80 deliveries), growing a little each time and holding 3 more waiting customers per level. Dots under a shop show its level.
- Easier to read: a first-game hint shows how to draw a road, and houses that can't reach a shop of their colour get a pulsing ring.
- Hold a house or shop, then drag it to move it; it lays its own short road to the nearest road. Tap or drag out of a shop to turn it, like a house.
- Make an account (username + password) to keep your progress on every phone.
- Pick your name when you first open it, then compete on global leaderboards (all-time and today's daily map). Levels, undo, pause-and-build.
- A shop: trade road tiles for roundabouts, traffic lights, motorways and bridges.

Everything is one file, `index.html`. No build step.

## Leaderboard setup (Supabase)

The leaderboard runs on a free Supabase project. The game talks to it straight from the browser, so there's no server to run. Players only pick a nickname. Each device keeps a random secret, so nobody can change anyone else's score.

It's already set up on the `routes` project (`vyyckdylaujxcbwxxijg`). To move it to a different project:

1. **SQL Editor → New query:** paste in [`supabase.sql`](supabase.sql) and press **Run**.
2. **Project Settings → API:** copy the **Project URL** and the **publishable key**. Both are meant to be public.
3. In `index.html`, set `SB_URL` and `SB_KEY` to those two values and push.

Without the keys, the game works normally and the leaderboard says it isn't switched on yet.

Accounts are username + password, checked inside the database (passwords are bcrypt-hashed, five wrong tries locks the account for a minute and longer after that). There's no email, so there's no password reset. Logging in on a phone that already has guest scores folds them into the account. Saves sync to the account, and stats are merged so an older phone can never lower them.

The SQL keeps the tables locked. The browser can only call three functions: post your score, post your daily score, and read the board. Scores only ever go up. Names are limited to 2–16 letters, numbers, spaces and `- _ .`. Daily scores are only accepted for today's map. These checks were tested against a real Postgres database.

## Hosting

Hosted on Render as a static site (`routes-game`), deployed from `main`. Every push goes live automatically.
