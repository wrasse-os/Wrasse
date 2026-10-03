#!/usr/bin/bash
# Print the complete installer image catalog (bootc-installer's /etc/bootc-installer/images.json)
# for one detected graphics flavor, built from .github/build-matrix.json so the installer offers
# exactly the images CI builds.
#
# NVIDIA is not a release line, it is a hardware variant of the same image. The live boot detects
# the flavor (wrasse-gpu-detect: wrasse = Mesa, wrasse-nvidia = open NVIDIA driver, Turing+) and
# build-iso.yml generates one catalog per flavor; wrasse-installer-config installs the matching one.
#
# Shape: a single "Wrasse" group (it carries the installer keys the leaves inherit; the installer's
# top level only takes groups) with one leaf per release line (Stable, Next, Reimagined, in
# build-matrix.json order) for the detected flavor, plus, only when the other flavor exists for
# at least one line, a last group "Use different graphics drivers" with the same lines for the
# other flavor. A line with "nvidia": false has no NVIDIA image: with the nvidia flavor detected its
# main leaf falls back to the wrasse image and says so.
# "default_image" is the detected flavor's stable leaf.
#
# Usage: installer/gen-catalog.sh <wrasse|wrasse-nvidia> [build-matrix.json]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flavor="${1:-}"
case "${flavor}" in
    wrasse | wrasse-nvidia) ;;
    *) echo "usage: gen-catalog.sh <wrasse|wrasse-nvidia> [build-matrix.json]" >&2; exit 2 ;;
esac
matrix="${2:-${root}/.github/build-matrix.json}"

jq -e '.lines | type == "object" and length > 0' "${matrix}" >/dev/null

jq --sort-keys --arg flavor "${flavor}" '
  def title: {"reimagined": "Reimagined", "next": "Next", "stable": "Stable"}[.] // (.[0:1] | ascii_upcase) + .[1:];
  def blurb: {
    "reimagined": "Newest Fedora branched release.",
    "next": "Newest Fedora beta.",
    "stable": "Newest Fedora final release."
  }[.] // "";
  def ref($img; $l): "ghcr.io/wrasse-os/\($img):\($l)";
  .lines as $lines
  | [ $lines | keys_unsorted[] ] as $all_lines
  | [ $all_lines[] | select($lines[.].nvidia == true) ] as $nvidia_lines
  | ($flavor == "wrasse-nvidia") as $nv
  | {
      default_image: ref(if $nv and ($lines.stable.nvidia == true) then "wrasse-nvidia" else "wrasse" end; "stable"),
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
            [ $all_lines[] as $l
              | if $nv and ($lines[$l].nvidia == true) then
                  { name: ($l | title), desc: "\($l | blurb) NVIDIA graphics driver included.", imgref: ref("wrasse-nvidia"; $l) }
                elif $nv then
                  { name: ($l | title), desc: "\($l | blurb) No NVIDIA image for this line yet, installs Mesa graphics (AMD, Intel, other).", imgref: ref("wrasse"; $l) }
                else
                  { name: ($l | title), desc: "\($l | blurb) Mesa graphics (AMD, Intel, other).", imgref: ref("wrasse"; $l) }
                end ]
            + (
              if $nv then
                [ {
                    name: "Use different graphics drivers",
                    subtitle: "Only if the detected choice is wrong for your GPU",
                    children: [ $all_lines[] as $l | { name: "\($l | title) (Mesa)", desc: "\($l | blurb) Mesa graphics (AMD, Intel, other).", imgref: ref("wrasse"; $l) } ]
                  } ]
              elif ($nvidia_lines | length) > 0 then
                [ {
                    name: "Use different graphics drivers",
                    subtitle: "Only if the detected choice is wrong for your GPU",
                    children: [ $nvidia_lines[] as $l | { name: "\($l | title) (NVIDIA)", desc: "\($l | blurb) NVIDIA graphics driver included (GTX 16 series, RTX and newer only).", imgref: ref("wrasse-nvidia"; $l) } ]
                  } ]
              else [] end
            )
          )
        }
      ]
    }
' "${matrix}"
