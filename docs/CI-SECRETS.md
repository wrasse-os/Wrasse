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

1. `/cosign.pub` is the Wrasse public key. Done.
2. The image ships the trust policy: `system_files/shared/usr/lib/pki/containers/wrasse.pub` (a copy of `/cosign.pub`), a
   `ghcr.io/wrasse-os` `sigstoreSigned` entry in `system_files/shared/etc/containers/policy.json`, and
   `registries.d/wrasse-os.yaml` with `use-sigstore-attachments: true`. So
   `bootc switch --enforce-container-sigpolicy ghcr.io/wrasse-os/wrasse` verifies. On key rotation, replace `/cosign.pub` and
   `wrasse.pub` together and keep the old key in the policy (`keyPaths`) until all supported images carry the new one, or older
   installs cannot pull. Never use `subjectRegExp` or keyless identities in this entry (they broke every pull in Bluefin,
   projectbluefin/common#1194); CI signs with the key, so the policy is key-based.
3. After the first push each package (`wrasse`, `wrasse-nvidia`) is created private. Set it public (Package settings, Change
   visibility) and under "Manage Actions access" make sure the `Wrasse` repository has Write access.
4. Actions settings: workflow permissions can stay "Read repository contents"; the workflow requests `packages: write`,
   `id-token: write`, `attestations: write` per job.

## What is verified with keys that are not yours

Base image, akmods and brew are cosign-verified in the build with Universal Blue's public keys, downloaded from their
repositories at build time. No secret is involved. If you want those keys pinned in-tree instead, that is a separate change.
