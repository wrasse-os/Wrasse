#!/usr/bin/bash
# Print the installer image catalog template (bootc-installer's /etc/bootc-installer/images.json)
# built from .github/build-matrix.json, so the installer offers exactly the images CI builds.
#
# Shape: one "Wrasse" group, two GPU groups (wrasse = Mesa, wrasse-nvidia = open NVIDIA driver),
# each with the release lines Reimagined / Next / Stable as leaves
# (ghcr.io/wrasse-os/<image>:<line>). A line whose "nvidia" is false gets no NVIDIA leaf.
# "default_image" is the placeholder @DEFAULT_IMAGE@; wrasse-installer-config fills it in at live boot
# from the GPU autodetect, which is what preselects the GPU group.
#
# Usage: installer/gen-catalog.sh [build-matrix.json]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
matrix="${1:-${root}/.github/build-matrix.json}"

jq -e '.lines | type == "object" and length > 0' "${matrix}" >/dev/null

jq --sort-keys '
  def title: {"reimagined": "Reimagined", "next": "Next", "stable": "Stable"}[.] // (.[0:1] | ascii_upcase) + .[1:];
  def blurb: {
    "reimagined": "Newest Fedora branched release",
    "next": "Newest Fedora beta",
    "stable": "Newest Fedora final release"
  }[.] // "";
  .lines as $lines
  | [ $lines | to_entries[] | select(.value.nvidia == true) | .key ] as $nvidia_lines
  | [ $lines | keys_unsorted[] ] as $all_lines
  | {
      default_image: "@DEFAULT_IMAGE@",
      fallback_flatpaks: [],
      images: [
        {
          name: "Wrasse",
          needs_user_creation: true,
          bootloader: "systemd",
          filesystem: "btrfs",
          composefs: true,
          filesystems: ["btrfs", "xfs"],
          children: (
            [ {
                name: "Wrasse (AMD, Intel, older NVIDIA)",
                subtitle: "Mesa graphics. Pick this if the preselected choice is wrong for your GPU.",
                children: [ $all_lines[] as $l | { name: ($l | title), desc: ($l | blurb), imgref: "ghcr.io/wrasse-os/wrasse:\($l)" } ]
              } ]
            + ( if ($nvidia_lines | length) > 0 then
                [ {
                    name: "Wrasse NVIDIA (Turing and newer)",
                    subtitle: "NVIDIA open driver. GTX 16 series, RTX and newer only.",
                    children: [ $nvidia_lines[] as $l | { name: ($l | title), desc: ($l | blurb), imgref: "ghcr.io/wrasse-os/wrasse-nvidia:\($l)" } ]
                  } ]
                else [] end )
          )
        }
      ]
    }
' "${matrix}"
