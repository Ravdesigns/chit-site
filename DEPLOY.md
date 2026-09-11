# Deploying the Chit site on ZopDay

Same shape as the Notchling site: a static site packaged as a container. ZopDay
builds the `Dockerfile` in this repo and runs it, on a Kubernetes cluster or on a
plain Linux VM.

**ZopCloud is the canonical host** and the one the Product Hunt listing points at.
Vercel is a mirror, and the only place `/api/hit` actually runs, because the
ZopCloud host serves static files only.

## Why its own hostname, again

Product Hunt refuses a second launch on a domain that already belongs to an
existing listing. Two are already spent:

| Host | Belongs to |
|---|---|
| `crew-deskmates.vercel.app` | Crew's listing (and the old `/worklog/` page) |
| `notchling.zopcloud.zop.dev` | Notchling's listing |

So Chit ships on **`chit.zopcloud.zop.dev`**, with `chit.vercel.app` as the
mirror and the analytics endpoint.

## Steps in the ZopDay console

1. Sign in at <https://zop.dev/signin> → **zopday**.
2. **Projects → New project** — name it `chit`.
3. **New environment** — pick the cluster/space or the VM target, and a namespace.
4. **Add deployment** — repository `https://github.com/Ravdesigns/chit-site`,
   branch `main`.
   Two accounts are in play and they are not interchangeable: the **site** repo
   is public on `Ravdesigns`, the same as `notchling-site`, because that is the
   setup ZopDay is proven to clone. The **app** repo is private on
   `sisodiaravindra10`, so `gh auth switch --user sisodiaravindra10` before any
   operation on that one.
5. ZopDay detects the `Dockerfile` and builds. If it asks for service settings:
   - **Container port:** `8080` (the image also honours an injected `$PORT`)
   - **Health check path:** `/healthz` → returns `200 ok`
6. **Deploy**, then watch the pipeline through to **Active**.
7. Set the hostname to `chit.zopcloud.zop.dev`.
8. Run `./verify-zopcloud.sh`. Do not submit to Product Hunt until it is green.

## Container facts

| Setting | Value |
|---|---|
| Base image | `nginx:1.27-alpine` |
| Listen port | `8080` (override with `PORT`) |
| Health endpoint | `/healthz` → `200 ok` |
| Custom 404 | yes (`404.html`) |
| Indexing | enabled; this is a public product page |
| Downloads | `Chit.zip`, 5 minute cache |

## The order that matters

`deploy.sh` rewrites the sha256 and the size on the page from the zip actually
present, so **rebuild the app first, copy the zip in, then deploy**:

```bash
cd ~/rav/chit && ./package.sh
cp dist/Chit.zip ~/rav/sites/chit/Chit.zip
cd ~/rav/sites/chit && ./deploy.sh      # Vercel mirror
git add -A && git commit -m "…" && git push   # ZopCloud rebuilds from the push
```

Deploying in the other order publishes a checksum that does not match the file
next to it, and a visitor who follows the trust instructions concludes the
download was tampered with.

## Still to do before launch

- [ ] `data-checkout` on `<body>` is empty, so the Pro button opens the email
      sheet. Paste the Gumroad URL in to switch it to real checkout.
- [ ] Pro is not gated in the app yet: history and statements are free in the
      current build, so the pricing section describes something that does not
      exist. Gate it or change the page.
- [ ] `share.png` (1200×630) is not made yet; the OG tags point at it.
