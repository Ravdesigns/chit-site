// Chit's own counter. No third-party analytics, no cookies, no identifiers —
// three tallies and a referring hostname.
//
// POST /api/hit?e=visit|download|install[&r=referrer]  → record one event
// GET  /api/hit                                        → totals, referrers, by-day
//
// Storage is APPEND-ONLY: one empty blob per event, named
//   chit/ev/<YYYY-MM-DD>/<event>/<host>/<random>
// and totals are computed by listing that prefix.
//
// It started as a single JSON counter doing read-modify-write, the same pattern as
// the other toys. That silently LOST events: Vercel Blob is eventually consistent
// on overwrite, so five posts a second apart counted as one, and a POST could
// report 4 while the next GET still said 3. Appending never reads before it
// writes, so nothing can race and nothing is lost.
//
// `install` is the tally that matters most: the curl one-liner never loads the
// page, so no JavaScript analytics product can see it at all.
import { put, list, del } from '@vercel/blob';

const ROOT = 'chit/ev';

// Events before this date were my pre-launch testing. They stay in storage (the
// Blob token is redacted by `vercel env pull` and injected via OIDC at runtime, so
// nothing local can delete them) but they are excluded from every total, which is
// the same thing as far as the dashboard is concerned.
// Launch day. Anything earlier is my own testing.
const COUNT_FROM = '2026-09-22';
// `pro` is intent, not a sale: somebody opened the Pro pane. Without it there is no
// way to tell a tier nobody wants from a tier nobody can figure out how to buy, and
// those two need completely different responses.
const EVENTS = ['visit', 'download', 'install', 'pro'];

// Hosts that are US. A `visit` whose referrer is one of these is not a visitor: it
// is a reload, an internal navigation, or me poking at my own page. On 9 Sep the
// counter logged 714 visits of which 691 were self-referred, which made a dead day
// look like a bigger spike than launch day and nearly went out as a public chart.
//
// Filtered at READ time on purpose. The store is append-only and the Blob token is
// injected at runtime, so nothing can retroactively delete events. Excluding them
// here makes every past tally honest too, without touching a single stored record.
const SELF_HOSTS = new Set([
  'chit.zopcloud.zop.dev',
  'chit.vercel.app',
  'localhost',
  '127.0.0.1',
]);

// Coarse hostname only — never a full URL or query string, which can carry
// personal data we have no business storing.
function refHost(raw) {
  if (!raw) return 'direct';
  try {
    const h = new URL(raw.startsWith('http') ? raw : `https://${raw}`)
      .hostname.replace(/^www\./, '').toLowerCase();
    return (h.replace(/[^a-z0-9.-]/g, '').slice(0, 60)) || 'direct';
  } catch { return 'other'; }
}

// `since` lets the pipeline prove itself before launch day. Without it the totals
// read zero until COUNT_FROM arrives, which is indistinguishable from a counter
// that silently does not work: exactly the thing you do not want to discover at
// 12:31 on launch morning. `?since=all` counts everything, test events included.
async function tally(since = COUNT_FROM) {
  // selfVisits is reported, not hidden: a number that suddenly balloons is the
  // signal that something on the page is reloading itself.
  const out = { visits: 0, downloads: 0, installs: 0, pros: 0, selfVisits: 0, refs: {}, days: {}, since };
  let cursor;
  do {
    const page = await list({ prefix: `${ROOT}/`, limit: 1000, cursor });
    for (const b of page.blobs) {
      // chit/ev/<date>/<event>/<host>/<random>
      const p = b.pathname.split('/');
      if (p.length < 6) continue;
      const [, , date, event, host] = p;
      if (!EVENTS.includes(event)) continue;
      if (date < since) continue;   // pre-launch test noise
      // An explicit map, not a ternary chain. The chain fell through to 'installs'
      // for anything it did not recognise, so adding a fourth event silently
      // inflated the install count instead of counting itself.
      const key = { visit: 'visits', download: 'downloads', install: 'installs', pro: 'pros' }[event];
      if (!key) continue;
      // Self-referred visits are noise. Downloads and installs are kept whatever
      // the referrer, because both take a deliberate act (a click, or piping a
      // script to bash) and neither can happen by reloading.
      if (event === 'visit' && SELF_HOSTS.has(host)) { out.selfVisits++; continue; }
      out[key]++;
      out.days[date] = out.days[date] || { visits: 0, downloads: 0, installs: 0, pros: 0 };
      out.days[date][key]++;
      if (event === 'visit') out.refs[host] = (out.refs[host] || 0) + 1;
    }
    cursor = page.hasMore ? page.cursor : undefined;
  } while (cursor);
  return out;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    if (req.method !== 'POST') {
      res.setHeader('Cache-Control', 'no-store');
        // ?since=all counts every event ever, including my pre-launch tests, so the
        // pipeline can be verified end to end. ?since=YYYY-MM-DD for any other window.
        const q = String(req.query.since || '');
        const since = q === 'all' ? '0000-00-00'
                    : /^\d{4}-\d{2}-\d{2}$/.test(q) ? q
                    : COUNT_FROM;
        return res.status(200).json({ ok: true, ...(await tally(since)) });
    }

    // Key-guarded reset. Only usable if NL_ADMIN_KEY is set by hand in the Vercel
    // dashboard — the CLI would not store a value for it. Without that, this always
    // 403s, which is the safe default. COUNT_FROM above is what actually hides the
    // pre-launch test events.
    if (req.query.reset) {
      const key = process.env.NL_ADMIN_KEY || '';
      if (!key || req.query.reset !== key) return res.status(403).json({ ok: false });
      let cursor, n = 0;
      do {
        const page = await list({ prefix: `${ROOT}/`, limit: 1000, cursor });
        if (page.blobs.length) { await del(page.blobs.map(b => b.url)); n += page.blobs.length; }
        cursor = page.hasMore ? page.cursor : undefined;
      } while (cursor);
      return res.status(200).json({ ok: true, cleared: n });
    }

    const e = String(req.query.e || '');
    if (!EVENTS.includes(e)) return res.status(400).json({ ok: false, error: 'unknown event' });

    const date = new Date().toISOString().slice(0, 10);
    const host = e === 'visit' ? refHost(req.query.r || req.headers.referer) : '_';
    const id = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;

    await put(`${ROOT}/${date}/${e}/${host}/${id}`, '1', {
      access: 'public', addRandomSuffix: false, contentType: 'text/plain',
      cacheControlMaxAge: 31536000,   // the blob never changes; cache it forever
    });
    return res.status(200).json({ ok: true, recorded: e });
  } catch {
    // A broken counter must never break the page or the installer.
    return res.status(200).json({ ok: false });
  }
}
