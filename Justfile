repo_organization := "wrasse-os"
rechunker_image := "ghcr.io/ublue-os/legacy-rechunk:v1.0.1-x86_64@sha256:2627cbf92ca60ab7372070dcf93b40f457926f301509ffba47a04d6a9e1ddaf7"
brew_image := "ghcr.io/ublue-os/brew:latest"
images := '(
    [wrasse]=wrasse
)'
flavors := '(
    [default]=default
    [nvidia]=nvidia
)'
tags := '(
    [reimagined]=reimagined
    [next]=next
    [stable]=stable
)'
export SUDOIF := if `id -u` == "0" { "" } else { "sudo" }
export PODMAN := if path_exists("/usr/bin/podman") == "true" { env("PODMAN", "/usr/bin/podman") } else if path_exists("/usr/bin/docker") == "true" { env("PODMAN", "docker") } else { env("PODMAN", "exit 1 ; ") }
export PULL_POLICY := if PODMAN =~ "docker" { "missing" } else { "newer" }
just := just_executable()

[private]
default:
    @{{ just }} --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	{{ just }} --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    {{ just }} --unstable --fmt --check -f Justfile

# Validate Shell Scripts with ShellCheck (requires: shellcheck)
[group('Just')]
validate-scripts:
    #!/usr/bin/bash
    set -eoux pipefail
    shellcheck build_files/**/*.sh .github/scripts/*.sh

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	{{ just }} --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    {{ just }} --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env

# Check if valid combo
[group('Utility')]
[private]
validate $image $tag $flavor:
    #!/usr/bin/bash
    set -eou pipefail
    declare -A images={{ images }}
    declare -A tags={{ tags }}
    declare -A flavors={{ flavors }}

    checkimage="${images[${image}]-}"
    checktag="${tags[${tag}]-}"
    checkflavor="${flavors[${flavor}]-}"

    # Validity Checks
    if [[ -z "$checkimage" ]]; then
        echo "Invalid Image..."
        exit 1
    fi
    if [[ -z "$checktag" ]]; then
        echo "Invalid tag..."
        exit 1
    fi
    if [[ -z "$checkflavor" ]]; then
        echo "Invalid flavor..."
        exit 1
    fi

# Build Image
[group('Image')]
build $image="wrasse" $tag="reimagined" $flavor="default" rechunk="0" ghcr="0" pipeline="0" $kernel_pin="":
    #!/usr/bin/bash

    echo "::group:: Build Prep"
    set -eoux pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    brew_image_sha=$(yq -r '.images[] | select(.name == "brew") | .digest' image-versions.yml)

    # Base Image
    base_image_name="silverblue"


    # Per-line settings (akmods flavor, kernel pin) live in the build matrix config
    akmods_flavor=$(jq -er --arg l "${tag}" '.lines[$l].akmods_flavor' .github/build-matrix.json)
    if [[ -z "${kernel_pin:-}" ]]; then
        kernel_pin=$(jq -r --arg l "${tag}" '.lines[$l].kernel_pin // ""' .github/build-matrix.json)
    fi

    # Fedora Version (FEDORA_VERSION from CI wins, else resolved for the line)
    fedora_version=$({{ just }} fedora_version '{{ image }}' '{{ tag }}' '{{ flavor }}' "${kernel_pin:-}")
    fedora_prerelease="${FEDORA_PRERELEASE:-}"
    if [[ -z "${fedora_prerelease}" ]]; then
        fedora_prerelease=$(.github/scripts/resolve-lines.sh prerelease "${tag}")
    fi

    # Base image: Fedora's own Silverblue bootc image (config: "base_image" in the build matrix). The floating
    # <fedora> tag always points at the newest compose (it equals the newest dated <fedora>.<date>.<n> tag), so
    # resolve it to a digest once, cosign-verify that digest with Fedora's published key, and build from the
    # digest. A missing tag or a failed verification fails closed, so this cell pushes nothing.
    base_image=$(jq -er '.base_image' .github/build-matrix.json)
    base_image_key=$(jq -er '.base_image_key' .github/build-matrix.json)
    if ! base_image_sha=$(skopeo inspect --retry-times 3 --format '{{ '{{.Digest}}' }}' docker://"${base_image}":"${fedora_version}"); then
        echo "::error::${base_image}:${fedora_version} does not exist; refusing to build this cell." >&2
        exit 1
    fi
    if [[ ! "${base_image_sha}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        echo "::error::Unexpected base image digest '${base_image_sha}'." >&2
        exit 1
    fi
    {{ just }} verify-container "${base_image##*/}@${base_image_sha}" "${base_image%/*}" "${base_image_key}"
    # Inspect the digest, not the tag, so the checks below describe exactly what gets built.
    base_json=$(skopeo inspect --retry-times 3 docker://"${base_image}"@"${base_image_sha}")
    # The tag must really be this Fedora release: never Rawhide (46 is Rawhide today), never a mislabeled image.
    base_kernel=$(jq -r '.Labels["ostree.linux"] // ""' <<<"${base_json}")
    base_version=$(jq -r '.Labels["org.opencontainers.image.version"] // ""' <<<"${base_json}")
    if [[ "${base_kernel}" != *".fc${fedora_version}."* || "${base_version}" != "${fedora_version}."* ]]; then
        echo "::error::${base_image}:${fedora_version} is not Fedora ${fedora_version} (ostree.linux='${base_kernel}', version='${base_version}'); refusing to build this cell." >&2
        exit 1
    fi
    # Rawhide must never be built, whatever the tag says (today 46 is Rawhide and shares its digest).
    rawhide_sha=$(skopeo inspect --retry-times 3 --format '{{ '{{.Digest}}' }}' docker://"${base_image}":rawhide)
    if [[ "${base_image_sha}" == "${rawhide_sha}" ]]; then
        echo "::error::${base_image}:${fedora_version} is Rawhide; refusing to build this cell." >&2
        exit 1
    fi

    # AKMODS: resolve the kernel and each image digest once, cosign-verify the
    # digests, and build from the digests only. The mutable tags are never read
    # again after this point (including inside the container build).
    AKMODS_ENV=$({{ just }} resolve-akmods "${akmods_flavor}" "${fedora_version}" "${flavor}" "${kernel_pin:-}")
    while IFS='=' read -r key value; do
        case "${key}" in
            KERNEL | AKMODS_DIGEST | AKMODS_NVIDIA_DIGEST | AKMODS_ZFS_DIGEST) declare "${key}=${value}" ;;
            *) echo "Unexpected resolve-akmods output: ${key}" >&2; exit 1 ;;
        esac
    done <<<"${AKMODS_ENV}"

    {{ just }} verify-container "brew:latest@${brew_image_sha}" ghcr.io/ublue-os https://raw.githubusercontent.com/ublue-os/brew/refs/heads/main/cosign.pub

    # Get Version
    ver="${tag}-${fedora_version}.$(date +%Y%m%d)"
    # A repository that has never been pushed to has no tags yet
    skopeo list-tags docker://ghcr.io/{{ repo_organization }}/${image_name} > /tmp/repotags.json || echo '{"Tags": []}' > /tmp/repotags.json
    if [[ $(jq "any(.Tags[]; contains(\"$ver\"))" < /tmp/repotags.json) == "true" ]]; then
        POINT="1"
        while $(jq -e "any(.Tags[]; contains(\"$ver.$POINT\"))" < /tmp/repotags.json)
        do
            (( POINT++ ))
        done
    fi
    if [[ -n "${POINT:-}" ]]; then
        ver="${ver}.$POINT"
    fi

    # Build Arguments
    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "AKMODS_FLAVOR=${akmods_flavor}")
    BUILD_ARGS+=("--build-arg" "AKMODS_DIGEST=${AKMODS_DIGEST}")
    BUILD_ARGS+=("--build-arg" "AKMODS_NVIDIA_DIGEST=${AKMODS_NVIDIA_DIGEST:-}")
    BUILD_ARGS+=("--build-arg" "AKMODS_ZFS_DIGEST=${AKMODS_ZFS_DIGEST:-}")
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=${base_image}")
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE_NAME=${base_image_name}")
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE_SHA=${base_image_sha}")
    BUILD_ARGS+=("--build-arg" "BREW_IMAGE={{ brew_image }}")
    BUILD_ARGS+=("--build-arg" "BREW_IMAGE_SHA=${brew_image_sha}")
    BUILD_ARGS+=("--build-arg" "FEDORA_MAJOR_VERSION=${fedora_version}")
    BUILD_ARGS+=("--build-arg" "FEDORA_PRERELEASE=${fedora_prerelease}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${image_name}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR={{ repo_organization }}")
    BUILD_ARGS+=("--build-arg" "KERNEL=${KERNEL}")
    BUILD_ARGS+=("--build-arg" "VERSION=${ver}")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    BUILD_ARGS+=("--build-arg" "UBLUE_IMAGE_TAG=${tag}")
    if [[ "${PODMAN}" =~ docker && "${TERM}" == "dumb" ]]; then
        BUILD_ARGS+=("--progress" "plain")
    fi

    # Labels
    LABELS=()
    LABELS+=("--label" "org.opencontainers.image.title=${image_name}")
    LABELS+=("--label" "org.opencontainers.image.version=${ver}")
    LABELS+=("--label" "ostree.linux=${KERNEL}")
    LABELS+=("--label" "io.artifacthub.package.readme-url=https://raw.githubusercontent.com/wrasse-os/Wrasse/refs/heads/main/README.md")
    LABELS+=("--label" "org.opencontainers.image.description=An agent-first, opinionated GNOME desktop built as a Fedora bootc image.")
    LABELS+=("--label" "containers.bootc=1")
    LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
    LABELS+=("--label" "org.opencontainers.image.source=https://raw.githubusercontent.com/wrasse-os/Wrasse/refs/heads/main/Containerfile")
    LABELS+=("--label" "org.opencontainers.image.url=https://github.com/wrasse-os/Wrasse")
    LABELS+=("--label" "org.opencontainers.image.vendor={{ repo_organization }}")
    LABELS+=("--label" "io.artifacthub.package.deprecated=false")
    LABELS+=("--label" "io.artifacthub.package.keywords=bootc,fedora,gnome,wrasse")

    echo "::endgroup::"
    echo "::group:: Build Container"

    # Build Image
    PODMAN_BUILD_ARGS=("${BUILD_ARGS[@]}" "${LABELS[@]}" --tag localhost/"${image_name}:${tag}" --file Containerfile)

    # Add GitHub token secret if available (for CI/CD)
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "Adding GitHub token as build secret"
        PODMAN_BUILD_ARGS+=(--secret "id=GITHUB_TOKEN,env=GITHUB_TOKEN")
    else
        echo "No GitHub token found - build may hit rate limit"
    fi

    # quay.io's CDN occasionally drops a blob mid-pull; podman's default of 3 quick retries was not enough in CI
    if [[ "${PODMAN}" =~ podman ]]; then
        PODMAN_BUILD_ARGS+=(--retry 5 --retry-delay 15s)
    fi

    ${PODMAN} build "${PODMAN_BUILD_ARGS[@]}" .
    echo "::endgroup::"

    # Rechunk
    if [[ "{{ rechunk }}" == "1" && "{{ ghcr }}" == "1" && "{{ pipeline }}" == "1" ]]; then
        ${SUDOIF} {{ just }} rechunk "${image}" "${tag}" "${flavor}" 1 1
    elif [[ "{{ rechunk }}" == "1" && "{{ ghcr }}" == "1" ]]; then
        ${SUDOIF} {{ just }} rechunk "${image}" "${tag}" "${flavor}" 1
    elif [[ "{{ rechunk }}" == "1" ]]; then
        ${SUDOIF} {{ just }} rechunk "${image}" "${tag}" "${flavor}"
    fi

# Build Image and Rechunk
[group('Image')]
build-rechunk image="wrasse" tag="reimagined" flavor="default" kernel_pin="":
    @{{ just }} build {{ image }} {{ tag }} {{ flavor }} 1 0 0 {{ kernel_pin }}

# Build Image with GHCR Flag
[group('Image')]
build-ghcr image="wrasse" tag="reimagined" flavor="default" kernel_pin="":
    #!/usr/bin/bash
    if [[ "${UID}" -gt "0" ]]; then
        echo "Must Run with sudo or as root..."
        exit 1
    fi
    {{ just }} build {{ image }} {{ tag }} {{ flavor }} 0 1 0 {{ kernel_pin }}

# Build Image for Pipeline:
[group('Image')]
build-pipeline image="wrasse" tag="reimagined" flavor="default" kernel_pin="":
    #!/usr/bin/bash
    ${SUDOIF} {{ just }} build {{ image }} {{ tag }} {{ flavor }} 1 1 1 {{ kernel_pin }}

# Rechunk Image
[group('Image')]
[private]
rechunk $image="wrasse" $tag="reimagined" $flavor="default" ghcr="0" pipeline="0":
    #!/usr/bin/bash

    echo "::group:: Rechunk Prep"
    set -eoux pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    # Check if image is already built
    ID=$(${PODMAN} images --filter reference=localhost/"${image_name}":"${tag}" --format "'{{ '{{.ID}}' }}'")
    if [[ -z "$ID" ]]; then
        {{ just }} build "${image}" "${tag}" "${flavor}"
    fi

    # Load into Rootful Podman
    ID=$(${SUDOIF} ${PODMAN} images --filter reference=localhost/"${image_name}":"${tag}" --format "'{{ '{{.ID}}' }}'")
    if [[ -z "$ID" && ! ${PODMAN} =~ docker ]]; then
        COPYTMP=$(mktemp -p "${PWD}" -d -t podman_scp.XXXXXXXXXX)
        ${SUDOIF} TMPDIR=${COPYTMP} ${PODMAN} image scp ${UID}@localhost::localhost/"${image_name}":"${tag}" root@localhost::localhost/"${image_name}":"${tag}"
        rm -rf "${COPYTMP}"
    fi

    # Prep Container
    CREF=$(${SUDOIF} ${PODMAN} create localhost/"${image_name}":"${tag}" bash)
    OLD_IMAGE=$(${SUDOIF} ${PODMAN} inspect $CREF | jq -r '.[].Image')
    OUT_NAME="${image_name}_build"
    MOUNT=$(${SUDOIF} ${PODMAN} mount "${CREF}")

    # Fedora Version
    fedora_version=$(${SUDOIF} ${PODMAN} inspect $CREF | jq -r '.[].Config.Labels["ostree.linux"]' | grep -oP 'fc\K[0-9]+')

    # Label Version
    VERSION=$(${SUDOIF} ${PODMAN} inspect $CREF | jq -r '.[].Config.Labels["org.opencontainers.image.version"]')

    # Git SHA
    SHA="dedbeef"
    if [[ -z "$(git status -s)" ]]; then
        SHA=$(git rev-parse HEAD)
    fi

    # Rest of Labels
    LABELS="
        io.artifacthub.package.deprecated=false
        io.artifacthub.package.keywords=bootc,fedora,gnome,wrasse
        io.artifacthub.package.readme-url=https://raw.githubusercontent.com/wrasse-os/Wrasse/refs/heads/main/README.md
        org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)
        org.opencontainers.image.license=Apache-2.0
        org.opencontainers.image.source=https://raw.githubusercontent.com/wrasse-os/Wrasse/refs/heads/main/Containerfile
        org.opencontainers.image.title=${image_name}
        org.opencontainers.image.url=https://github.com/wrasse-os/Wrasse
        org.opencontainers.image.vendor={{ repo_organization }}
        ostree.linux=$(${SUDOIF} ${PODMAN} inspect $CREF | jq -r '.[].Config.Labels["ostree.linux"]')
        containers.bootc=1
    "

    # Cleanup Space during Github Action
    if [[ "{{ ghcr }}" == "1" ]]; then
        base_image=$(jq -er '.base_image' .github/build-matrix.json)
        ID=$(${SUDOIF} ${PODMAN} images --filter reference="${base_image}":${fedora_version} --format "{{ '{{.ID}}' }}")
        if [[ -n "$ID" ]]; then
            ${PODMAN} rmi "$ID"
        fi
    fi

    # Rechunk Container
    rechunker="{{ rechunker_image }}"

    echo "::endgroup::"
    echo "::group:: Prune"

    # Run Rechunker's Prune
    ${SUDOIF} ${PODMAN} run --rm \
        --pull=${PULL_POLICY} \
        --security-opt label=disable \
        --volume "$MOUNT":/var/tree \
        --env TREE=/var/tree \
        --user 0:0 \
        "${rechunker}" \
        /sources/rechunk/1_prune.sh

    echo "::endgroup::"
    echo "::group:: Create ostree tree"

    # Run Rechunker's Create
    ${SUDOIF} ${PODMAN} run --rm \
        --security-opt label=disable \
        --volume "$MOUNT":/var/tree \
        --volume "cache_ostree:/var/ostree" \
        --env TREE=/var/tree \
        --env REPO=/var/ostree/repo \
        --env RESET_TIMESTAMP=1 \
        --user 0:0 \
        "${rechunker}" \
        /sources/rechunk/2_create.sh

    # Cleanup Temp Container Reference
    ${SUDOIF} ${PODMAN} unmount "$CREF"
    ${SUDOIF} ${PODMAN} rm "$CREF"
    ${SUDOIF} ${PODMAN} rmi "$OLD_IMAGE"

    echo "::endgroup::"
    echo "::group:: Rechunker"

    # Run Rechunker
    ${SUDOIF} ${PODMAN} run --rm \
        --pull=${PULL_POLICY} \
        --security-opt label=disable \
        --volume "$PWD:/workspace" \
        --volume "$PWD:/var/git" \
        --volume cache_ostree:/var/ostree \
        --env REPO=/var/ostree/repo \
        --env PREV_REF=ghcr.io/{{ repo_organization }}/"${image_name}":"${tag}" \
        --env OUT_NAME="$OUT_NAME" \
        --env LABELS="${LABELS}" \
        --env "DESCRIPTION='An interpretation of the Ubuntu spirit built on Fedora technology'" \
        --env "VERSION=${VERSION}" \
        --env VERSION_FN=/workspace/version.txt \
        --env OUT_REF="oci:$OUT_NAME" \
        --env GIT_DIR="/var/git" \
        --env REVISION="$SHA" \
        --user 0:0 \
        "${rechunker}" \
        /sources/rechunk/3_chunk.sh

    # Fix Permissions of OCI
    ${SUDOIF} find ${OUT_NAME} -type d -exec chmod 0755 {} \; || true
    ${SUDOIF} find ${OUT_NAME}* -type f -exec chmod 0644 {} \; || true

    if [[ "${UID}" -gt "0" ]]; then
        ${SUDOIF} chown "${UID}:${GROUPS}" -R "${PWD}"
    elif [[ -n "${SUDO_UID:-}" ]]; then
        chown "${SUDO_UID}":"${SUDO_GID}" -R "${PWD}"
    fi

    # Remove cache_ostree
    ${SUDOIF} ${PODMAN} volume rm cache_ostree

    echo "::endgroup::"

    # Pipeline Checks
    if [[ {{ pipeline }} == "1" && -n "${SUDO_USER:-}" ]]; then
        sudo -u "${SUDO_USER}" {{ just }} load-rechunk "${image}" "${tag}" "${flavor}"
        sudo -u "${SUDO_USER}" {{ just }} secureboot "${image}" "${tag}" "${flavor}"
    fi

# Load OCI into Podman Store
[group('Image')]
load-rechunk image="wrasse" tag="reimagined" flavor="default":
    #!/usr/bin/bash
    set -eou pipefail

    # Validate
    {{ just }} validate {{ image }} {{ tag }} {{ flavor }}

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    # Load Image
    OUT_NAME="${image_name}_build"
    IMAGE=$(${PODMAN} pull oci:"${PWD}"/"${OUT_NAME}")
    ${PODMAN} tag ${IMAGE} localhost/"${image_name}":{{ tag }}

    # Cleanup
    rm -rf "${OUT_NAME}*"
    rm -f previous.manifest.json

# Run Container
[group('Image')]
run $image="wrasse" $tag="reimagined" $flavor="default":
    #!/usr/bin/bash
    set -eoux pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    # Check if image exists
    ID=$(${PODMAN} images --filter reference=localhost/"${image_name}":"${tag}" --format "'{{ '{{.ID}}' }}'")
    if [[ -z "$ID" ]]; then
        {{ just }} build "$image" "$tag" "$flavor"
    fi

    # Run Container
    ${PODMAN} run -it --rm localhost/"${image_name}":"${tag}" bash

# Test Changelogs
[group('Changelogs')]
changelogs branch="stable" handwritten="":
    #!/usr/bin/bash
    set -eou pipefail
    python3 ./.github/changelogs.py "{{ branch }}" ./output.env ./changelog.md --workdir . --handwritten "{{ handwritten }}"

# Verify Container with Cosign
[group('Utility')]
verify-container container="" registry="ghcr.io/ublue-os" key="":
    #!/usr/bin/bash
    set -eou pipefail

    # Get Cosign if Needed
    if [[ ! $(command -v cosign) ]]; then
        COSIGN_CONTAINER_ID=$(${SUDOIF} ${PODMAN} create cgr.dev/chainguard/cosign:latest bash)
        ${SUDOIF} ${PODMAN} cp "${COSIGN_CONTAINER_ID}":/usr/bin/cosign /usr/local/bin/cosign
        ${SUDOIF} ${PODMAN} rm -f "${COSIGN_CONTAINER_ID}"
    fi

    # Verify Cosign Image Signatures if needed
    if [[ -n "${COSIGN_CONTAINER_ID:-}" ]]; then
        if ! cosign verify --certificate-oidc-issuer=https://token.actions.githubusercontent.com --certificate-identity=https://github.com/chainguard-images/images/.github/workflows/release.yaml@refs/heads/main cgr.dev/chainguard/cosign >/dev/null; then
            echo "NOTICE: Failed to verify cosign image signatures."
            exit 1
        fi
    fi

    # Public Key for Container Verification
    key={{ key }}
    if [[ -z "${key:-}" ]]; then
        key="https://raw.githubusercontent.com/ublue-os/main/main/cosign.pub"
    fi

    # Verify Container using cosign public key
    if ! cosign verify --key "${key}" "{{ registry }}"/"{{ container }}" >/dev/null; then
        echo "NOTICE: Verification failed. Please ensure your public key is correct."
        exit 1
    fi

# Secureboot Check
[group('Utility')]
secureboot $image="wrasse" $tag="reimagined" $flavor="default":
    #!/usr/bin/bash
    set -eou pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name ${image} ${tag} ${flavor})

    # Get the vmlinuz to check
    kernel_release=$(${PODMAN} inspect "${image_name}":"${tag}" | jq -r '.[].Config.Labels["ostree.linux"]')
    TMP=$(${PODMAN} create "${image_name}":"${tag}" bash)
    ${PODMAN} cp "$TMP":/usr/lib/modules/"${kernel_release}"/vmlinuz /tmp/vmlinuz
    ${PODMAN} rm "$TMP"

    # Get the Public Certificates
    curl --retry 3 -Lo /tmp/kernel-sign.der https://github.com/ublue-os/akmods/raw/main/certs/public_key.der
    curl --retry 3 -Lo /tmp/akmods.der https://github.com/ublue-os/akmods/raw/main/certs/public_key_2.der
    openssl x509 -in /tmp/kernel-sign.der -out /tmp/kernel-sign.crt
    openssl x509 -in /tmp/akmods.der -out /tmp/akmods.crt

    # Make sure we have sbverify
    CMD="$(command -v sbverify)"
    if [[ -z "${CMD:-}" ]]; then
        temp_name="sbverify-${RANDOM}"
        ${PODMAN} run -dt \
            --entrypoint /bin/sh \
            --volume /tmp/vmlinuz:/tmp/vmlinuz:z \
            --volume /tmp/kernel-sign.crt:/tmp/kernel-sign.crt:z \
            --volume /tmp/akmods.crt:/tmp/akmods.crt:z \
            --name ${temp_name} \
            alpine:edge
        ${PODMAN} exec ${temp_name} apk add sbsigntool
        CMD="${PODMAN} exec ${temp_name} /usr/bin/sbverify"
    fi

    # Confirm that Signatures Are Good
    $CMD --list /tmp/vmlinuz
    returncode=0
    if ! $CMD --cert /tmp/kernel-sign.crt /tmp/vmlinuz || ! $CMD --cert /tmp/akmods.crt /tmp/vmlinuz; then
        echo "Secureboot Signature Failed...."
        returncode=1
    fi
    if [[ -n "${temp_name:-}" ]]; then
        ${PODMAN} rm -f "${temp_name}"
    fi
    exit "$returncode"

# Resolve akmods digests once and cosign-verify them. Prints shell assignments
# (KERNEL, AKMODS_DIGEST, AKMODS_NVIDIA_DIGEST, AKMODS_ZFS_DIGEST) on stdout.
# Fails closed: a missing image or a failed verification exits non-zero.
[group('Utility')]
[private]
resolve-akmods akmods_flavor fedora_version flavor kernel_pin="":
    #!/usr/bin/bash
    set -eou pipefail

    akmods_flavor="{{ akmods_flavor }}"
    fedora_version="{{ fedora_version }}"
    kernel_pin="{{ kernel_pin }}"

    # Kernel release: the pin, else the one the rolling akmods tag currently carries.
    # This is the only place a mutable tag is read.
    if [[ -n "${kernel_pin}" ]]; then
        kernel_release="${kernel_pin}"
    else
        kernel_release=$(skopeo inspect --retry-times 3 docker://ghcr.io/ublue-os/akmods:"${akmods_flavor}"-"${fedora_version}" | jq -r '.Labels["ostree.linux"]') || kernel_release=""
    fi
    if [[ ! "${kernel_release}" =~ ^[0-9A-Za-z._-]+$ ]]; then
        echo "::error::No akmods image for ${akmods_flavor}-${fedora_version}; refusing to build this cell." >&2
        exit 1
    fi

    # Tag to digest, once, then verify the digest.
    resolve() {
        local name="$1" digest
        if ! digest=$(skopeo inspect --retry-times 3 --format '{{ '{{.Digest}}' }}' docker://ghcr.io/ublue-os/"${name}":"${akmods_flavor}"-"${fedora_version}"-"${kernel_release}"); then
            echo "::error::${name}:${akmods_flavor}-${fedora_version}-${kernel_release} does not exist; refusing to build this cell." >&2
            exit 1
        fi
        if [[ ! "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
            echo "::error::Unexpected digest '${digest}' for ${name}." >&2
            exit 1
        fi
        {{ just }} verify-container "${name}@${digest}" >&2
        echo "${digest}"
    }

    # Assign before printing so a failed resolve stops the recipe (set -e does
    # not see failures inside echo "$(...)").
    akmods_digest=$(resolve akmods)
    echo "KERNEL=${kernel_release}"
    echo "AKMODS_DIGEST=${akmods_digest}"
    if [[ "{{ flavor }}" =~ nvidia ]]; then
        nvidia_digest=$(resolve akmods-nvidia-open)
        echo "AKMODS_NVIDIA_DIGEST=${nvidia_digest}"
    fi
    if [[ "${akmods_flavor}" =~ coreos ]]; then
        zfs_digest=$(resolve akmods-zfs)
        echo "AKMODS_ZFS_DIGEST=${zfs_digest}"
    fi

# Get Fedora Version of a release line
[group('Utility')]
[private]
fedora_version image="wrasse" tag="reimagined" flavor="default" $kernel_pin="":
    #!/usr/bin/bash
    set -eou pipefail
    {{ just }} validate {{ image }} {{ tag }} {{ flavor }}
    if [[ -n "${kernel_pin:-}" ]]; then
        fedora_version=$(echo "${kernel_pin}" | grep -oP 'fc\K[0-9]+')
    elif [[ -n "${FEDORA_VERSION:-}" ]]; then
        fedora_version="${FEDORA_VERSION}"
    else
        fedora_version=$(.github/scripts/resolve-lines.sh version "{{ tag }}")
    fi
    echo "${fedora_version}"

# Image Name
[group('Utility')]
[private]
image_name image="wrasse" tag="reimagined" flavor="default":
    #!/usr/bin/bash
    set -eou pipefail
    {{ just }} validate {{ image }} {{ tag }} {{ flavor }}
    if [[ "{{ flavor }}" == "default" ]]; then
        image_name={{ image }}
    else
        image_name="{{ image }}-{{ flavor }}"
    fi
    echo "${image_name}"

# Generate Tags
[group('Utility')]
generate-build-tags image="wrasse" tag="reimagined" flavor="default" kernel_pin="" ghcr="0" $version="" github_event="" github_number="":
    #!/usr/bin/bash
    set -eou pipefail

    FEDORA_VERSION="$({{ just }} fedora_version '{{ image }}' '{{ tag }}' '{{ flavor }}' '{{ kernel_pin }}')"
    # Use Build Version from Rechunk
    if [[ -z "${version:-}" ]]; then
        version="{{ tag }}-${FEDORA_VERSION}.$(date +%Y%m%d)"
    fi
    version=${version#{{ tag }}-}

    # Commit Tags (pull requests build but never push)
    github_number="{{ github_number }}"
    SHA_SHORT="$(git rev-parse --short HEAD)"
    COMMIT_TAGS=()
    if [[ "{{ ghcr }}" == "1" ]]; then
        COMMIT_TAGS+=(pr-${github_number:-}-{{ tag }}-${version})
        COMMIT_TAGS+=(${SHA_SHORT}-{{ tag }}-${version})
    fi

    # Release line tags: the line itself, plus dated variants
    BUILD_TAGS=("{{ tag }}" "{{ tag }}-${version}" "{{ tag }}-${version:3}")

    if [[ "{{ github_event }}" == "pull_request" ]]; then
        alias_tags=("${COMMIT_TAGS[@]}")
    else
        alias_tags=("${BUILD_TAGS[@]}")
    fi

    echo "${alias_tags[*]}"

# Generate Default Tag
[group('Utility')]
generate-default-tag tag="reimagined" ghcr="0":
    #!/usr/bin/bash
    set -eou pipefail

    echo "{{ tag }}"

# Tag Images
[group('Utility')]
tag-images image_name="" default_tag="" tags="":
    #!/usr/bin/bash
    set -eou pipefail

    # Get Image, and untag
    IMAGE=$(${PODMAN} inspect localhost/{{ image_name }}:{{ default_tag }} | jq -r .[].Id)
    ${PODMAN} untag localhost/{{ image_name }}:{{ default_tag }}

    # Tag Image
    for tag in {{ tags }}; do
        ${PODMAN} tag $IMAGE {{ image_name }}:${tag}
    done


    # Show Images
    ${PODMAN} images

# Extract Container and generate SBOM
[group('Utility')]
gen-sbom $image="wrasse" $tag="reimagined" $flavor="default" $syft_cmd="syft":
    #!/usr/bin/bash
    set -eoux pipefail

    image_name=$({{ just }} image_name '{{ image }}' '{{ tag }}' '{{ flavor }}')

    OUT_DIR="sbom_out/${image_name}"
    mkdir -p "${OUT_DIR}"

    # We have to do it this stupid way because we are OOMing on github runners
    # https://github.com/anchore/syft/issues/3800
    ${PODMAN} container create --replace --name ${image_name} "${image_name}:${tag}"

    ROOTFS="${OUT_DIR}/rootfs"
    mkdir -p "${ROOTFS}"

    ${PODMAN} export ${image_name} | tar -C "${ROOTFS}" -xf -
    ${PODMAN} container rm ${image_name}

    SBOM="${OUT_DIR}/sbom.json"

    ${syft_cmd} --source-name "${image_name}:${tag}" "${OUT_DIR}" -o syft-json=${SBOM}
    du -sh "${SBOM}"

    rm -rf "${ROOTFS}"

# DNF CI package cache
[group('Utility')]
setup-cache $image="wrasse" $tag="reimagined" $ghcr="0" $github_event="0":
    #!/usr/bin/bash
    set -eou pipefail

    image_name=$({{ just }} image_name '{{ image }}')
    fedora_version=$({{ just }} fedora_version '{{ image }}' '{{ tag }}')

    ALLOW_CACHE_WRITE="false"

    BLESSED_IMAGE=wrasse

    if [[ "${image_name}" == "${BLESSED_IMAGE}" ]] && \
       [[ "{{ ghcr }}" == "1" ]] && \
       [[ "${github_event}" == "workflow_dispatch" || "${github_event}" == "schedule" ]]; then
        ALLOW_CACHE_WRITE="true"
    fi

    CACHE_NAME="${BLESSED_IMAGE}-${fedora_version}"

    echo "${CACHE_NAME}" "${ALLOW_CACHE_WRITE}"

# Examples:
#   > just retag-nvidia-on-ghcr stable stable-44.20260702 0
#   > just retag-nvidia-on-ghcr reimagined reimagined-45.20261001 0
#
# working_tag: The tag of the most recent known good image (e.g., stable-44.20260702)
# stream:      One of reimagined, next, or stable
# dry_run:     Only print the skopeo commands instead of running them
#
# First generate a PAT with package write access (https://github.com/settings/tokens)
# and set $GITHUB_USERNAME and $GITHUB_PAT environment variables

# Retag images on GHCR
[group('Admin')]
retag-nvidia-on-ghcr working_tag="" stream="" dry_run="1":
    #!/bin/bash
    set -euxo pipefail
    skopeo="echo === skopeo"
    if [[ "{{ dry_run }}" -ne 1 ]]; then
        echo "$GITHUB_PAT" | podman login -u $GITHUB_USERNAME --password-stdin ghcr.io
        skopeo="skopeo"
    fi
    for image in wrasse-nvidia; do
      $skopeo copy docker://ghcr.io/{{ repo_organization }}/${image}:{{ working_tag }} docker://ghcr.io/{{ repo_organization }}/${image}:{{ stream }}
    done
