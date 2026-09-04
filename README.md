# FulDC++ website + update server

Static site for [FulDC++](download.html) plus the files the in-client auto-updater fetches.
Served by **GitHub Pages** at `https://fuldcpp.net/`.

## Layout

```
index.html  features.html  plugins.html                    the site
download.html  changelog.html
assets/                                                     css + logo/favicon
download/   FulDC-<ver>-x64.zip                             fresh-install package
update/     version.xml  version.xml.sign                   updater manifest + signature
update/updater/ updater_x64_<ver>.zip                       self-update payload
update/beta/ update/nightly/                                legacy channels - see below
.nojekyll                                                   serve files verbatim
.gitattributes                                              keep version.xml LF-exact
.gitignore                                                  keeps the signing key out
CNAME                                                       custom domain
```

### `update/beta/` and `update/nightly/` — do not delete

There is only one real channel. These two directories hold byte-identical copies of the stable
manifest and signature, and the client no longer has an update-channel setting (it was removed
because choosing beta or nightly silently kept you on stable anyway).

They must stay published regardless. Clients built before that change still read their saved
`UPDATE_CHANNEL` and request `update/beta/version.xml` or `update/nightly/version.xml`; if those
404, the version check just fails with a logged warning and those installs stop being offered
updates **permanently and silently**. Refresh the copies whenever you publish a stable release —
same two files, copied verbatim, signature included.

## First-time setup

1. Push this repo, enable **GitHub Pages** (branch = `main`, folder = `/`).
2. Add a `CNAME` file containing your domain and point DNS at GitHub Pages.
3. Turn on **Enforce HTTPS** (the updater uses `https://` URLs).
4. Replace every `fuldcpp.net` placeholder (this README, `update/version.xml`, `download.html`
   is relative so it's fine) with the real domain.

## One-time: create the FulDC++ signing key

The updater only trusts a `version.xml` signed with the private key whose public half is baked
into the client (`airdcpp/airdcpp/core/crypto/pubkey.h`). Do this once, keep `air_rsa` secret.

> **The key never lives in this repository.** This is a public GitHub Pages repo; a key generated
> in the working tree is one `git add -A` away from being published, and it cannot be rotated
> afterwards without abandoning every existing install. Keep it outside the checkout and pass an
> absolute path to every command below. The working copy lives at `c:\airdc-ng\keys\air_rsa`;
> `.gitignore` also lists the usual key patterns, but that is a backstop, not the control.

1. Generate a 2048-bit RSA private key (PEM), outside the repo. The filename **must** be
   `air_rsa`:
   ```
   openssl genrsa -out c:\airdc-ng\keys\air_rsa 2048
   ```
2. Use the client's own tooling to emit the matching `pubkey.h` (byte format must match exactly).
   Run any existing `FulDC.exe` once against the template version.xml:
   ```
   FulDC.exe /sign update\version.xml c:\airdc-ng\keys\air_rsa -pubout
   ```
   → writes `pubkey.h` next to `version.xml`.
3. Copy that `pubkey.h` over `airdcpp/airdcpp/core/crypto/pubkey.h` in the client source and
   **rebuild** (`cmake --build --preset=x64-release`). The rebuilt exe is your first real release;
   from now on it trusts only updates signed by `air_rsa`.

> Store `air_rsa` somewhere safe and backed up. Lose it and you can never ship a self-installing
> update to existing clients again (they'd reject anything signed by a new key). Never commit it.

## Publishing a release (see project plan Part C)

1. Build `x64-release` → `compiled/x64-release/windows/FulDC.exe`.
2. Copy `update/version.template.xml` → your build output dir as `version.xml`.

   > **CRITICAL — `<Title>` and `<Message>` MUST be *inside* `<VersionInfo>`** (see the template),
   > not direct children of `<DCUpdate>`. The client's `announceVersion()` searches for them while
   > positioned inside `<VersionInfo>`; if they're outside, the "update available" dialog **never
   > appears** (silently — no error). This is how AirDC++'s own manifest is structured.
3. Run `/createupdate` **from the staged application directory** — a copy of the folder the
   release zip is built from, not the build output:
   ```
   <staged>\FulDC.exe /createupdate --resource-directory="<staged>" --output-directory="...\out"
   ```
   This produces `updater_x64_<ver>.zip`, fills in `version.xml` (Build / VersionString / TTH /
   download URL), converts it to **LF** endings and signs it with `air_rsa` → `version.xml.sign`.

   > **Why the staged directory, and not `compiled\...\windows` plus `installer`.** The package is
   > assembled from two places: `Node.js`, `FulDC.exe` and `FulDC.pdb` come from the directory of
   > the *running* executable, and `Themes`, `Web-resources`, `EmoPacks`, `Language` and
   > `fuldc.jpg` from `--resource-directory`. The build output has no `Node.js` at all (it has
   > been carried from one release payload to the next since 1.098) and its `FulDC.pdb` is the
   > linker's full ~385 MB one rather than the stripped copy; `installer\` has no `fuldc.jpg`.
   > Only the staged folder holds a correct copy of everything, so run it from there. Every
   > missing piece is reported in a **message box**, not on the console, so a run that fails from
   > a script looks like a bare exit code 1.

   > Run it from a **copy** of the staged folder. Starting an executable inside the folder the
   > release zip is built from creates a profile there — a per-user TLS key and CID — and the
   > staging script's identity check will then refuse to build the zip.

   > `/createupdate` looks for the key at `<output-directory>\air_rsa` — it takes no key argument
   > (`UpdaterCreator::createUpdate`). So copy `c:\airdc-ng\keys\air_rsa` into the **output
   > directory** first, and delete it from there once the signature is generated. The output
   > directory is a build folder; the key must never be copied into this repo, which is public.
4. Commit the three generated files here:
   - `update/version.xml`  (overwrites the template — **must stay LF, byte-exact**)
   - `update/version.xml.sign`
   - `update/updater/updater_x64_<ver>.zip`
   Also drop a fresh-install ZIP in `download/` and bump the version on `download.html`.

   > **NEVER include a `Settings` folder (or `Certificates/`, `*.key`, `DCPlusPlus.xml`,
   > `country_ip_db.mmdb`, logs) in the download ZIP.** A running client populates `Settings`
   > with a **unique per-user TLS private key** and personal config — shipping it leaks that key
   > to everyone and gives all users the same identity. The download must contain ONLY:
   > `FulDC.exe`, `FulDC.pdb` (the stripped one), `Node.js`, `Themes`, `Web-resources`, `EmoPacks`,
   > `Language` (the translations; an empty one means the staging script did not copy them).
   > Build it from the compiled output but copy those items explicitly — do **not** copy the whole
   > `compiled/.../windows/` folder (it contains build junk + any test-run `Settings`).
5. After pushing, verify: `curl https://fuldcpp.net/update/version.xml | file -` shows no CRLF; the
   download ZIP contains no `Settings`/`*.key`; and an old client offered the higher `Build`
   accepts and self-installs.

## Publishing a plugin release

Plugins live in a separate repo, [fuldcpp/plugins](https://github.com/fuldcpp/plugins), and are
**not** hosted here — `plugins.html` links straight at the GitHub release asset.

1. In the plugins repo, tag the release `<plugin>-v<version>` (e.g. `squiggle-v2.4`) and upload the
   packaged `.dcext` produced by that plugin's `pack.ps1` as the release asset.
2. Update the plugin's card on `plugins.html`: the `.pver` pill, the size in `.pmeta`, and both
   URLs (`/releases/download/<tag>/<file>.dcext` and `/releases/tag/<tag>`).

The download URL embeds the tag, so step 2 is not optional — miss it and the page keeps serving the
previous version. Verify with `curl -I <url>`: a 302 to `release-assets.githubusercontent.com` is
correct, a 404 means the tag or asset name is wrong.

> The private key `air_rsa` is **never** committed. The matching public key is embedded in the
> client (`airdcpp/airdcpp/core/crypto/pubkey.h`); only updates signed by `air_rsa` are trusted.

## Extension catalog

Web extensions (the npm-style packages run by the web server) are catalogued in
[fuldcpp/extensions](https://github.com/fuldcpp/extensions) and served from
`https://extensions.fuldcpp.net/` by a Cloudflare Worker deployed from that repository - not
from this site. Publishing steps live in that repository's README; nothing here changes when
the catalog does.
