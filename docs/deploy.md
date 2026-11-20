# Deploying Artsy Neighbor to Fly.io (private preview)

The runbook for the private preview: how it was set up on 2026-11-02,
how to deploy changes, how to look at it, and how to tear it down and
rebuild it. Written so that someone who has never deployed anything
can follow it top to bottom.

**Status:** written right after the first deploy; teardown and
rebuild (sections 8 and 4) tried for real on 2026-11-04, which
created the current app `an-preview-g3ukxp`. Sections marked
*(not yet tried)* still need a real run-through.

Never put a password or connection string in this file. Secrets live
in Fly (and in the developer's Passwords app), nowhere in the repo.

---

## 1. What runs where

```
Browser ──HTTPS──▶ Fly proxy ──▶ app Machine (an-preview-g3ukxp, San Jose)
                                   │  Phoenix release, 1 GB, sleeps when idle
                                   │
                                   └─private network─▶ database Machine
                                                       (an-preview-g3ukxp-db, San Jose)
                                                       Postgres 17 + 1 GB volume
```

| Piece | Name | Notes |
|---|---|---|
| Fly organization | `personal` | account anna@anna-kazantseva.com (signs in via GitHub) |
| Web app | `an-preview-g3ukxp` | address https://an-preview-g3ukxp.fly.dev |
| Database app | `an-preview-g3ukxp-db` | unmanaged Fly Postgres, image `flyio/postgres-flex:17` |
| Region | `sjc` (San Jose) | Fly no longer offers Seattle; the database must be in the same region as the app |

**Why these choices** (details in `NOTES.md`, "Order of work" step 2):

- **Hard-to-guess name + site-wide password.** The developer's own
  domain is deliberately not used yet. Every request, including
  images, needs the site password first
  (`ArtsyNeighborWeb.Plugs.SitePassword`).
- **One app Machine** (`--ha=false`). Fly's default is two. With two,
  live updates (PubSub) need clustering first (see `NOTES.md`).
- **Unmanaged Postgres** (~$2–4/month) instead of Managed Postgres
  ($38/month minimum). Fly marks it "unsupported": backups are our job
  (section 7).
- **Postgres 17, pinned.** The Mac has Postgres.app 17, and `pg_dump`
  can't back up a newer server. Fly's default may be 18.

**Rough cost:** about US$9–11/month in total (since the app Machine
went from 512 MB to 1 GB on 2026-11-15, about $3 more), less while
the app Machine sleeps. The database Machine runs all the time.

**Photos** are stored on Tigris (two buckets, `$APP-photos` and
`$APP-originals`): set up, checked and undone as described in the
separate runbook **`docs/tigris.md`**.

## 2. Known limitations of the preview

- **No email.** The mailer is still the dev "Local" adapter, which is
  off in production. Registering, email log-in links and anything else
  that sends mail fails. Log in with email + password. (Real email:
  "Order of work" step 5.)
- **Uploaded photos were lost on every deploy and restart** until
  photos moved to Tigris (`docs/tigris.md`, 2026-11). The app
  Machine's disk is rebuilt from the image each time.
- **The database starts empty.** `seeds.exs` is dev-only on purpose
  (it deletes everything first). The admin account is created by hand
  (section 5); sample categories, artists and works can then be added
  with one command (section 5.1).
- `HOME_HERO_PRODUCT_ID` isn't set, so the home page picture shows
  without a credit or link. Set it once the hero work exists in this
  database: `fly secrets set HOME_HERO_PRODUCT_ID=<id>`.

---

## 3. One-time setup on the Mac

1. **Install the `fly` tool** (official script; downloads a ready-made
   program into `~/.fly/bin`, no Homebrew):

   ```
   curl -L https://fly.io/install.sh | sh
   ```

2. **Add it to the PATH**: paste at the end of `~/.zshrc`, then open a
   new terminal (or run `source ~/.zshrc`):

   ```
   # Fly.io command-line tool (flyctl)
   export FLYCTL_INSTALL="/Users/annak/.fly"
   export PATH="$FLYCTL_INSTALL/bin:$PATH"
   ```

   Check: `fly version`. (`fly` and `flyctl` are the same program.)

3. **Log in**: `fly auth login` (opens the browser). Check:
   `fly auth whoami`. The login token is stored in
   `~/.fly/config.yml`. Treat it like a password: it gives full access
   to the apps.

4. **Payment method**: add a card on the Fly dashboard, under Billing.

---

## 4. Creating the preview from scratch

Run everything from the project folder (the one with `mix.exs`), so
`fly` finds `fly.toml`.

**The `$APP` variable.** The commands below use `$APP` wherever the
app's name goes. `APP=...` saves a piece of text under the name `APP`
in the current terminal window, and `$APP` puts it back into a
command. It lasts until that window is closed. In a new window, set
it again from `fly.toml` (which records the name once the app exists):

```
APP=$(grep "^app = " fly.toml | cut -d"'" -f2)
echo $APP        # should print the app's name, e.g. an-preview-g3ukxp
```

(`grep` finds the line `app = '...'`; `cut -d"'" -f2` keeps the text
between the first pair of single quotes.)

**Photos:** before the first deploy (4.5), set up photo storage as in
`docs/tigris.md` §3. The app refuses to start without its settings.

### 4.1 Code that must already be in the repo

Done in commits `68cb39f`, `7a41159` and `bddd52c`; listed here so a
rebuild knows what it relies on:

- `Dockerfile`, `.dockerignore`, `rel/overlays/bin/{server,migrate}`,
  `lib/artsy_neighbor/release.ex`, from `mix phx.gen.release --docker`.
  - `.dockerignore` was extended so `.env`, `priv/static/uploads/`
    and local working folders are never sent to the builder.
  - The Windows `.bat` scripts were deleted. **`fly launch` recreates
    them; delete them again** (`rel/overlays/bin/*.bat`).
- The Dockerfile's `ELIXIR_VERSION` / `OTP_VERSION` must match the Mac
  (`elixir --version`). Images are listed under `hexpm/elixir` on
  Docker Hub.
- The site password plug, `ArtsyNeighborWeb.Plugs.SitePassword`
  (`lib/artsy_neighbor_web/plugs/site_password.ex`), switched on in
  `lib/artsy_neighbor_web/endpoint.ex` before `Plug.Static`, plus the
  block in `config/runtime.exs` that makes the app refuse to start in
  production without `SITE_USERNAME` and `SITE_PASSWORD`.
- `fly.toml` and `rel/env.sh.eex`, created by `fly launch` (next
  step). On a rebuild with these already in the repo, see the note at
  the end of 4.2.

### 4.2 Create the app (no cost yet)

Make a new hard-to-guess name and keep it in `$APP`:

```
APP="an-preview-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"
echo $APP
```

How it works, from the inside out:
- `/dev/urandom` is an endless stream of random bytes from the
  operating system;
- `tr -dc 'a-z0-9'` deletes (`-d`) every character that is *not*
  (`-c`) a lowercase letter or digit;
- `LC_ALL=C` makes macOS's `tr` treat each byte as a plain character
  (without it: "Illegal byte sequence");
- `head -c 6` keeps the first 6 and stops the endless stream;
- `$( ... )` puts the result into the text.

36 possible characters in 6 places is about 2 billion names: too many
to guess, short enough to type.

Then:

```
fly launch --no-deploy --name $APP --region sjc --org personal \
  --ha=false --vm-memory 1024 \
  --no-db --no-redis --no-object-storage --no-github-workflow --yes
```

| Flag | Why |
|---|---|
| `--no-deploy` | only set things up; nothing is built or started |
| `--ha=false` | one Machine, not two |
| `--vm-memory 1024` | 1 GB. Was 512 MB until 2026-11-15, when processing two phone photos at once ran out of memory (`docs/tigris.md` §3.5); 256 is too tight even without photos |
| `--no-db` | **important**: otherwise it may create Managed Postgres ($38/month) |
| `--no-redis --no-object-storage` | not needed yet |
| `--no-github-workflow` | no automatic deploy on every push; deploys stay manual |
| `--yes` | accept the remaining questions with these choices |

What it does:
- creates the app at Fly;
- sets the `SECRET_KEY_BASE` secret (the key that signs login cookies);
- writes `fly.toml` (the app's settings at Fly) and `rel/env.sh.eex`;
- recreates the `.bat` files (delete them).

**About `rel/env.sh.eex`:** a template that `mix release` turns into
the release's `env.sh` (the `<%= ... %>` parts are filled in at build
time). It runs before every start of `bin/server`, `bin/migrate` and
`bin/artsy_neighbor remote`, and only on Fly (`FLY_APP_NAME` is set).
It sets:
- `RELEASE_NODE`: the running app's name on the network, which is how
  the remote console (section 5) finds it;
- `DNS_CLUSTER_QUERY`: where to look for other Machines of the app
  (clustering, see `NOTES.md`);
- `ERL_AFLAGS` and `ECTO_IPV6`: use IPv6, the only kind of address on
  Fly's private network, for Machine-to-Machine and **database**
  connections (without `ECTO_IPV6` the app can't reach Postgres).

`git diff` afterwards: it should not have changed the Dockerfile or
any config.

**Rebuilding when `fly.toml` is already in the repo** (tried
2026-11-04): delete it first, with `rm fly.toml`. It's in git, so nothing
is lost. Run `fly launch` exactly as above, and it writes a fresh
`fly.toml` with the new name. Then run `git diff fly.toml`: the only
differences should be the app name, `PHX_HOST` and the date on the
first line. Look at anything else before deploying. `rel/env.sh.eex`
may be rewritten the same way; `git diff` shows that too.

### 4.3 Site password (the developer types this, never in chat)

Choose a username (not secret, shared with testers) and a passphrase
(e.g. 5 random words joined with hyphens; easy to type on a phone).
To generate one in your own terminal:

```
grep -E '^[a-z]{4,7}$' /usr/share/dict/words | sort -R | head -5 | paste -sd- -
```

Save both in Passwords, then:

```
fly secrets set SITE_USERNAME='<username>' SITE_PASSWORD='<passphrase>'
```

Single quotes pass the text exactly as typed. Before the first deploy,
secrets show as "Staged". Check with `fly secrets list` (it shows
names only, never values).

### 4.4 Database (costs start here)

Create it (the developer runs this; it prints the `postgres` admin
password **once**):

```
fly postgres create --name $APP-db --region sjc --org personal \
  --image-ref flyio/postgres-flex:17 --initial-cluster-size 1 \
  --vm-size shared-cpu-1x --vm-memory 256 --volume-size 1
```

| Flag | Why |
|---|---|
| `--image-ref flyio/postgres-flex:17` | Postgres 17 to match the Mac's `pg_dump`; the tag follows the newest 17.x |
| `--initial-cluster-size 1` | one database Machine (3 = high availability, $80+/month) |
| `--vm-memory 256` | smallest size, enough for a tiny database |
| `--volume-size 1` | 1 GB disk; can grow later, never shrink |

**Save the Password and Connection string** from the final box in
Passwords (e.g. "artsy-neighbor fly DB admin"). This is the database
server's administrator, not a site account.

Check it's up:

```
fly status -a $APP-db       # 1 machine, started, primary, checks passing
fly volumes list -a $APP-db # pg_data, 1GB, sjc, encrypted
fly image show -a $APP-db   # label fly.pg-version=17.x
```

Connect it to the app:

```
fly postgres attach $APP-db -a $APP
```

This creates a database and a limited database user for the app, and
sets the `DATABASE_URL` secret. It prints the connection string,
**including that user's password**: don't paste this output anywhere
(if it happens, change the password, section 6). There's no need to
save it: Fly keeps it in the secret, and the admin
login can always reset it. `fly secrets list` should now show four
secrets: `SECRET_KEY_BASE`, `SITE_USERNAME`, `SITE_PASSWORD`,
`DATABASE_URL`.

### 4.5 First deploy

```
fly deploy --ha=false
```

What happens (the first time takes about 5–10 minutes; later deploys
are faster thanks to cached layers):

1. The project folder (minus `.dockerignore`) is uploaded to Fly's
   builder (Depot).
2. The Dockerfile runs: libraries compile, then our code, then the
   CSS/JS (`mix assets.deploy`), then `mix release`. The final image
   was 104 MB.
3. The image is pushed to `registry.fly.io/$APP`.
4. `release_command` (`/app/bin/migrate`) runs in a temporary Machine.
   If a migration fails, the deploy stops and the old version keeps
   running.
5. The app Machine is created (first time) or updated, and started.

Expected harmless lines in the app's log: `Failed open sctp dynamic
library: libsctp.so.1` and `Reaped child process ... SIGUSR1`.

### 4.6 Check it

```
curl -s -o /dev/null -w "%{http_code}\n" https://$APP.fly.dev/
# 401 = the site password is working
```

Open the address (`echo https://$APP.fly.dev` prints it) in a
browser: the login box appears,
then the (empty) home page.

---

## 5. Creating the admin account on the live site

The production database starts with no users. Create the admin from a
console inside the running app. Type everything yourself, straight
into the console (not via an editor, which may share the text).

```
fly ssh console                      # a shell inside the app Machine
/app/bin/artsy_neighbor remote       # an iex> prompt inside the running app
```

`fly ssh console` uses your Fly login, so no password is needed.
`remote` connects to the already-running app, so **everything typed
there acts on production data for real**.

Paste **one line at a time** (a multi-line paste failed the first
time). The password must be at least 12 characters, and different
from the site passphrase:

```elixir
alias ArtsyNeighbor.{Repo, Accounts.User, Accounts.Admin}
```
```elixir
user = %User{} |> User.registration_changeset(%{email: "<email>", username: "<username>"}) |> User.password_changeset(%{password: "<password>"}) |> User.confirm_changeset() |> Repo.insert!()
```
```elixir
Repo.insert!(%Admin{user_id: user.id})
```

Leave with Ctrl+C twice, then `exit`.

**If the account already exists** because you registered on the site
first: registration saves the user but then crashes on the
confirmation email (see `NOTES.md`, Known bugs), so the user stays
unconfirmed and has no password. Instead of the `Repo.insert!` line
above, finish that account (find its id with the check below):

```elixir
user = Repo.get!(User, <id>)
```
```elixir
user = user |> User.password_changeset(%{password: "<password>"}) |> User.confirm_changeset() |> Repo.update!()
```
then `Repo.insert!(%Admin{user_id: user.id})` as above. (Done this
way on 2026-11-04.)

Check it from the Mac (read-only):

```
fly ssh console -C "/app/bin/artsy_neighbor rpc 'import Ecto.Query; IO.inspect(ArtsyNeighbor.Repo.all(from a in ArtsyNeighbor.Accounts.Admin, join: u in assoc(a, :user), select: {u.username, u.email}))'"
```

Then log in on the site with email + **password** (not the email link)
and open `/admin`.

### 5.1 Filling the preview with sample data (optional)

To give the preview something to look at (e.g. for people helping
with the site's looks), add the sample data: the 7 categories, 13
made-up artists (the six original seed artists, the developer's own
studio and the six demo artists) and their 81 works with photos. It
is `ArtsyNeighbor.SampleData`, the same data `seeds.exs` puts on the
Mac. Do this after section 5, so the studio can be linked to the admin
account.

```
fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.add_sample_data()'"
```

What to expect:

- **It only adds.** Nothing existing is changed or deleted; the admin
  account and anything made by hand stay. A category or artist that's
  already there is skipped, so running it again is safe.
- **It takes a few minutes.** All 105 photos go through the normal
  photo processing into Tigris (30 seconds on the Mac; slower on the
  preview's shared CPU). It prints a line or two per artist; wait for
  the last line, "Sample artists log in with ...". Each photo also
  writes a "Photo stored" line to `fly logs`. While it runs, photo
  uploads on the site wait their turn.
- **If an artist fails** (e.g. a photo can't be processed, or the
  site is busy), whatever was added of that artist is removed again,
  photos included, and it goes on with the next one. The end of the
  output then lists them under "NOT ADDED", with the reasons above it;
  running the command again retries them. Also if the terminal
  connection drops: run it again.
- **Logins.** Each sample artist logs in with their email (in
  `priv/repo/sample_data/`) and the password `DevPassword1!`. That
  password is in the repository, which is fine only while the repo is
  private and the site password keeps everyone else out. They must be
  removed before anyone else is invited (below, and section 10).
- **The developer's studio** ("Anna's Magnificent Art Studio") is
  linked to the admin account, so logging in as admin shows its vendor
  dashboard. If the admin account already has an artist profile, the
  studio gets its own login instead, `anna.demo@example.com`; the output
  says which.
- **It refuses on a real site**: it only runs on an app whose name
  contains "preview". And it needs `rpc` (inside the running site, which
  has the photo limiter and the Tigris settings), not `eval`.

**Removing the sample data again** (e.g. before testers, if the
database isn't started over):

```
fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.remove_sample_data()'"
```

It hard-deletes every sample artist (also one that was renamed) with
their works, orders, conversations and reviews, and their photos from
Tigris, and **locks** every sample account: its password is replaced by
a random one nobody knows and it is logged out everywhere. (Locked, not
deleted: the site can't delete accounts yet; see `NOTES.md`, item 9 of
"Features".) The admin account and the categories stay. Then check:

```
fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.check_before_launch()'"
```

It prints "OK: no sample data left", or lists what's left and stops
with "NOT READY". It also checks that no temporary trial page (in a
folder such as `priv/static/trials/`, as the photo-shrinking trial
was until 2026-11-20) is still served: "OK: no trial pages served", or
what to remove.

Hard-deleting a single sample artist in `/admin` is not enough on its
own: it removes the artist and their photos, but their login keeps
working.

---

## 6. Everyday use

### Deploying a change

1. `mix precommit` passes and the change is committed.
2. `fly deploy --ha=false` (`--ha=false` is harmless once the single
   Machine exists, and keeps a second one from appearing).
3. Look at the change the way a visitor would: open the site's address
   in the browser (or run `fly open`, which opens it for you), enter
   the site password, and go to the page that changed. If something
   looks wrong (an error page, missing styles), run `fly logs` to see
   what the app is saying, like the terminal where `mix phx.server`
   runs on the Mac. (`fly ssh console` is not for this: it opens a
   command prompt inside the Machine, not the website.)

### Look-only commands (safe to run any time)

| Command | Shows |
|---|---|
| `fly apps list` | all apps |
| `fly status` | the app's Machines: state, region, version |
| `fly status -a $APP-db` | the database Machine |
| `fly logs` | the app's live log (Ctrl+C to stop) |
| `fly logs --no-tail` | recent log lines, then exit |
| `fly secrets list` | secret names, never values |
| `fly releases` | deploy history |
| `fly machines list` | Machines, more detail |
| `fly volumes list -a $APP-db` | the database disk |
| `fly image show -a $APP-db` | exact image and Postgres version |
| `fly dashboard` | the app's page on fly.io |

`-a <name>` picks the app; without it, `fly` uses the one in
`fly.toml`. The `$APP-db` commands need `$APP` set in that terminal
first (see the start of section 4).

### Changing the app's database password (done 2026-11-04)

For the limited user the app connects as (`an_preview_g3ukxp`), e.g.
after its connection string was pasted somewhere. The `postgres`
admin password is a different one and doesn't change. The app can't
reach the database between steps 2 and 3, which is fine on the
preview.

1. New password, letters and digits only (safe inside the URL):
   `LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; echo`.
   No need to save it: Fly keeps it in the secret.
2. `fly postgres connect -a $APP-db`, then at the `postgres=#` prompt
   `\password an_preview_g3ukxp` (paste twice; `\password` sends it
   already scrambled, so it stays out of any history), then `\q`.
3. `fly secrets import`, paste one line
   `DATABASE_URL=postgres://an_preview_g3ukxp:<NEW>@an-preview-g3ukxp-db.flycast:5432/an_preview_g3ukxp?sslmode=disable`,
   Enter, then Ctrl+D. Typed this way, the password stays out of the
   shell history. Fly restarts the app.
4. `fly logs --no-tail | tail -20` (no database errors) and reload
   the site.

### Rolling back *(not yet tried)*

`fly releases --image` lists earlier images. Redeploy one with
`fly deploy --image <image-ref>`. Note: this doesn't undo database
migrations.

---

## 7. Backups

First done for real on 2026-11-03: a dump taken and restored into a
scratch database on the Mac, with every table, all 46 migrations, the
admin user and a test category present. The database was nearly empty
then, so repeat it once there is real data.

Two layers:

### 7.1 Fly's automatic snapshots (nothing to do)

Fly takes a daily snapshot of the database disk (a "volume") by
itself and keeps each one for **5 days** (the first 10 GB a month
are free). To look at them:

```
fly volumes list -a $APP-db                              # shows the volume id (vol_...)
fly volumes snapshots list <volume-id> -a $APP-db
```

The `-a $APP-db` on the second command matters: without it, `fly`
uses the app from `fly.toml` (the web app, not the database) and
says the volume "does not belong to app".

These snapshots live at Fly, in the same place as the database. They
protect against mistakes, not against losing the Fly account. That's
what our own copy is for.

### 7.2 Our own copy on the Mac (`pg_dump`)

Dumps are kept in **`~/Backups/artsy-neighbor/`** on the Mac: outside
the repo, so a dump can never be committed by accident, and covered
by Time Machine once that is set up. The admin password comes from
the developer's Passwords app.

**Terminal 1: open a private tunnel and leave it running.**
```
fly proxy 15432:5432 -a $APP-db
```
`localhost:15432` on the Mac now leads to port 5432 on the database
at Fly (which is not reachable from the internet otherwise). The Mac
side uses 15432 because Postgres.app already uses 5432 for the dev
database, so `localhost:5432` = dev and `localhost:15432` = live. The
tunnel lasts only while this command runs; Ctrl+C closes it. Wait for
`Proxying local port 15432` before going on.

**Terminal 2: take the dump.**
```
mkdir -p ~/Backups/artsy-neighbor
cd ~/Backups/artsy-neighbor
pg_dump -h localhost -p 15432 -U postgres -d an_preview_g3ukxp -Fc -f artsy-neighbor-$(date +%F).dump
```
It asks `Password:`. Paste the admin password; nothing shows while
typing, which is normal. Keeping the password out of the command
line keeps it out of the shell history too.

What each piece means:

| Piece | Meaning |
|---|---|
| `mkdir -p ~/Backups/artsy-neighbor` | Creates the folder (and `~/Backups` above it). `-p` = no error if it already exists. |
| `cd ~/Backups/artsy-neighbor` | Moves into it, so the dump file lands there. |
| `pg_dump` | Postgres's backup tool (from Postgres.app). Reads a whole database and writes it to one file. |
| `-h localhost` | **Host**: connect to this Mac. |
| `-p 15432` | **Port 15432**: the tunnel's end, which `fly proxy` forwards to the real database at Fly. (5432 would be the dev database.) |
| `-U postgres` | **User**: log in as `postgres`, the database admin. This is why it asks for the admin password. |
| `-d an_preview_g3ukxp` | **Database** name on the server: the app name with underscores (checked 2026-11-02 with `select current_database()`; `fly postgres attach` also named the app's database user the same). |
| `-Fc` | **Format: custom**. A compressed file that `pg_restore` can read, and it can restore just parts if needed. Without it you get a large plain-text SQL file. |
| `-f artsy-neighbor-….dump` | **File** to write to. |
| `$(date +%F)` | The shell runs `date +%F` first and puts its output in place: today's date, e.g. `2026-11-03`. Each day's backup gets its own name. |

Then check the file and close the tunnel:
```
ls -lh                                   # the new .dump file and its size
pg_restore --list artsy-neighbor-<date>.dump | head -12    # header: which database, which versions
```
Ctrl+C in Terminal 1 closes the tunnel.

The Mac's `pg_dump` must be the **same major version as the server
or newer** (2026-11-04: Postgres.app 17.6, server 17.7; see
section 9).

### 7.3 Checking a backup by restoring it

A backup only counts once it has been restored. Into a throwaway
database on the Mac (Postgres.app needs no password locally; the dev
database `artsy_neighbor_dev` isn't touched):

```
createdb an_restore_test
pg_restore --no-owner --no-privileges -d an_restore_test ~/Backups/artsy-neighbor/artsy-neighbor-<date>.dump
```

`--no-owner --no-privileges` skip the "who owns / who may use this
table" lines. The live database's user (`an_preview_g3ukxp`) doesn't
exist on the Mac, and without these flags the restore prints a page
of harmless but alarming errors.

Then compare with the repo:
```
psql -d an_restore_test -c "select count(*), max(version) from schema_migrations;"
ls priv/repo/migrations | wc -l          # same count? latest file = max(version)?
psql -d an_restore_test -c "select email, status from users;"
```
Something recognisable made on the live site just before the dump
(e.g. a test category) should be there too.

Finally, delete the throwaway database. `dropdb` doesn't ask for
confirmation, so type the name carefully:
```
dropdb an_restore_test
psql -l                                  # an_restore_test is no longer listed
```

**For now:** no regular schedule. While the preview holds no real
data, Fly's snapshots are enough, plus a manual dump before anything
risky (a migration, the Postgres 18 move). Where regular backups
should live (probably not only the laptop), how often, and how many
to keep gets decided together with Neon vs. our own Postgres and with
image storage on Tigris (`NOTES.md`, "Order of work" step 2 c).

---

## 8. Tearing it down (done 2026-11-04)

**Destroys all data. Take a backup first** if anything is worth
keeping.

```
fly apps destroy $APP
fly apps destroy $APP-db     # removes the database and its volume
```

Also remove the photo buckets (`docs/tigris.md` §6) and check
`fly storage list`.

Then check `fly apps list` and the Billing page. Rebuilding = section
4 again with a new name.

### Starting the database over, keeping the app *(not yet done)*

Planned before inviting testers, so they start on a clean site. Every
photo in the buckets belongs to the old database, so the buckets must
be emptied at the same time, or their files stay there forever with no
row pointing to them (`NOTES.md` #42). The simplest safe way: destroy
both buckets and create them again as in `docs/tigris.md` §3.2–3.3,
along with the new database (section 4.4). Write the exact steps here
when it's done.

---

## 9. Keeping things current

- **Elixir and Erlang:** the Mac (Homebrew) and the `Dockerfile` must
  use the same versions. Update both together.
- **Postgres:** the Mac (Postgres.app) and the Fly image move together,
  17 → 18 later (see `NOTES.md`).
- **Libraries:** `mix hex.outdated`, then update, `mix precommit`,
  deploy.
- **The Debian base image** (`DEBIAN_VERSION` in the Dockerfile) gets
  security fixes. Move to a newer `trixie-YYYYMMDD-slim` tag now and
  then.

## 10. Before inviting testers (pointers to NOTES.md)

- Real email (step 5), backups of the photo buckets (`docs/tigris.md`), backups
  repeated with real data and a schedule decided (section 7 above).
- Decide on one or two Machines (two needs clustering).
- Managed Postgres or Neon instead of unmanaged, if worth the cost.
- The form-recovery check, since every deploy drops open connections.
- Sample data (section 5.1): before the site password comes off or
  the repo stops being private, start the database over (section 8), or
  run `remove_sample_data()`; then `check_before_launch()` must say
  "OK". The sample accounts' password is in the repository.
