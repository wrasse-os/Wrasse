# CI secrets and one-time setup (you create these; CI never does)

Nothing here has been created. The workflow `.github/workflows/build.yml` reads exactly these names.

## Repository secrets (github.com/wrasse-os/Wrasse, Settings, Secrets and variables, Actions)

| Name | Required | What it is |
|---|---|---|
| `SIGNING_SECRET` | yes, for any push to `main`/schedule/dispatch | The cosign **private key** file contents (`cosign.key`). Used by `cosign sign --key env://COSIGN_PRIVATE_KEY` on every image and on every SBOM. |
| `COSIGN_PASSWORD` | yes if the key has a password; otherwise create it empty or leave it unset | The password cosign needs to decrypt `SIGNING_SECRET`. The workflow passes it as `COSIGN_PASSWORD`. |

`GITHUB_TOKEN` is automatic (push to GHCR, SBOM upload, attestations use OIDC). No personal access token is needed.
Pull requests never read the signing secrets and never push.

Create the key pair on a trusted machine (fish):

```fish
cosign generate-key-pair
# writes cosign.key (private, goes into SIGNING_SECRET) and cosign.pub (public)
```

Do not commit `cosign.key`.

## Things to do in the repo and org (not secrets)

1. Replace `/cosign.pub` in the repo root with the new public key. The checked-in file is Bluefin's.
2. Ship the public key and trust policy in the image so `bootc switch --enforce-container-sigpolicy ghcr.io/wrasse-os/wrasse`
   actually verifies. Today `system_files/shared/etc/containers/policy.json` only verifies `ghcr.io/ublue-os`;
   `ghcr.io/wrasse-os` falls through to `insecureAcceptAnything`. Needed: a `wrasse-os.pub` under
   `/usr/lib/pki/containers/`, a `ghcr.io/wrasse-os` `sigstoreSigned` entry in `policy.json`, and a matching
   `registries.d` file with `use-sigstore-attachments: true`. This is not done (it needs your public key).
3. After the first push each package (`wrasse`, `wrasse-nvidia`) is created private. Set it public (Package settings, Change
   visibility) and under "Manage Actions access" make sure the `Wrasse` repository has Write access.
4. Actions settings: workflow permissions can stay "Read repository contents"; the workflow requests `packages: write`,
   `id-token: write`, `attestations: write` per job.

## What is verified with keys that are not yours

Base image, akmods and brew are cosign-verified in the build with Universal Blue's public keys, downloaded from their
repositories at build time. No secret is involved. If you want those keys pinned in-tree instead, that is a separate change.
