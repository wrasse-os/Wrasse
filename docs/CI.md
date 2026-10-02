# CI: release lines and image matrix

One git branch (`main`). Every channel is an image tag produced by one build matrix in `.github/workflows/build.yml`.

| Line | Fedora version | Image tags |
|---|---|---|
| `stable` | newest final Fedora | `stable`, `stable-<fedora>.<date>`, `stable-<date>` |
| `next` | newest Fedora beta; stays on the last one until the next beta | `next`, ... |
| `reimagined` | newest branched Fedora (never Rawhide); with none, whatever `next` is | `reimagined`, ... |

Images: `ghcr.io/wrasse-os/wrasse` and `ghcr.io/wrasse-os/wrasse-nvidia`. Each line x flavor is an independent matrix cell.

## Config

`.github/build-matrix.json` has one entry per line: `akmods_flavor`, `kernel_pin` (empty = follow the akmods tag) and
`nvidia` (true/false). Setting a line's `nvidia` to `false` drops that line's nvidia image; it is the only switch.
`reimagined` currently has `nvidia: true`. That is a placeholder, not a decision (see the pending decisions in `SPEC.md`).

## How versions are resolved

`.github/scripts/resolve-lines.sh` (run once in the `plan` job, and by `just` for local builds):

- final = highest Fedora release in state `current` in Bodhi (`bodhi.fedoraproject.org/releases/`);
- branched = a `pending` Bodhi release whose branch is not `rawhide`;
- beta = a `NN_Beta/` directory under `dl.fedoraproject.org/pub/fedora/linux/releases/test/` for an `NN` newer than final.

Any lookup failure fails the `plan` job, so nothing is built from a guessed version.

## Fail closed

`just build` resolves the base image and each akmods image to a digest once and builds from the digest. The akmods digests are
cosign-verified. The base is `quay.io/fedora-ostree-desktops/silverblue:<fedora version>` (`base_image` in `.github/build-matrix.json`).
Its floating tag is resolved to a digest once and verified with Fedora's published key, vendored at
`.github/keys/quay.io-fedora-ostree-desktops.pub` (source: `gitlab.com/fedora/ostree/ci-test/-/raw/main/quay.io-fedora-ostree-desktops.pub`).
The floating tag is used rather than a dated tag because it always equals the newest `<fedora>.<date>.<n>` tag, and the digest pin is what
makes the build reproducible. The build also checks the base's `ostree.linux` and version labels against the requested release and refuses
a digest equal to the `rawhide` tag's. Whether a line is final, beta or branched still comes from the resolver (Bodhi and
`releases/test/NN_Beta/`); the base tag only supplies the image, and `FEDORA_PRERELEASE` is set for any non-final version.
What the Fedora base lacks compared with ublue's `silverblue-main` is added by `build_files/base/01-fedora-base.sh`.

If an image does not exist for that Fedora version and kernel, or verification fails, the cell exits before any push.
Its tag keeps pointing at the last good image. Other cells are unaffected (`fail-fast: false`); the `Summary` job turns the
run red so the failure is visible.

## Local builds

`just build wrasse stable default` resolves the version itself. Override with `FEDORA_VERSION=44 just build ...`.
