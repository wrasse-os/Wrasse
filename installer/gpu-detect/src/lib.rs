//! Decide which Wrasse image flavor the installer should preselect.
//!
//! Turing or newer NVIDIA GPU (the ones the open kernel modules support) -> `wrasse-nvidia`.
//! Everything else (AMD, Intel, older NVIDIA, no GPU found) -> `wrasse`.
//! The user can override with `wrasse.gpu=nvidia|default|auto` on the kernel command line, the
//! `WRASSE_GPU` environment variable, or `/etc/wrasse/installer-gpu`.

use std::fs;
use std::path::Path;

mod nvidia_open_ids;
pub use nvidia_open_ids::{NVIDIA_OPEN_DEVICE_IDS, NVIDIA_OPEN_TAG};

pub const NVIDIA_VENDOR: u16 = 0x10de;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Flavor {
    Default,
    Nvidia,
}

impl Flavor {
    /// The image name under `ghcr.io/wrasse-os/`.
    pub fn image_name(self) -> &'static str {
        match self {
            Flavor::Default => "wrasse",
            Flavor::Nvidia => "wrasse-nvidia",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Override {
    Auto,
    Flavor(Flavor),
}

/// A PCI display device as found in sysfs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PciGpu {
    pub vendor: u16,
    pub device: u16,
}

/// Parse a sysfs hex value such as `0x10de\n` or `0x030000\n`.
fn parse_hex(s: &str) -> Option<u32> {
    let t = s.trim();
    let t = t.strip_prefix("0x").or_else(|| t.strip_prefix("0X")).unwrap_or(t);
    u32::from_str_radix(t, 16).ok()
}

/// Every display-class (base class 0x03: VGA, 3D controller, other) PCI device under
/// `<sysfs>/bus/pci/devices`. NVIDIA's HDMI audio function (class 0x04) is not a GPU and is skipped.
pub fn read_gpus(sysfs: &Path) -> Vec<PciGpu> {
    let dir = sysfs.join("bus/pci/devices");
    let Ok(entries) = fs::read_dir(&dir) else {
        return Vec::new();
    };
    let mut gpus = Vec::new();
    for entry in entries.flatten() {
        let p = entry.path();
        let read = |name: &str| fs::read_to_string(p.join(name)).ok().and_then(|s| parse_hex(&s));
        let (Some(vendor), Some(device), Some(class)) = (read("vendor"), read("device"), read("class")) else {
            continue;
        };
        if class >> 16 != 0x03 {
            continue;
        }
        gpus.push(PciGpu { vendor: vendor as u16, device: device as u16 });
    }
    gpus.sort_by_key(|g| (g.vendor, g.device));
    gpus
}

/// True when the device is an NVIDIA GPU the open kernel modules support (Turing and newer).
pub fn is_nvidia_open_supported(gpu: &PciGpu) -> bool {
    gpu.vendor == NVIDIA_VENDOR && NVIDIA_OPEN_DEVICE_IDS.binary_search(&gpu.device).is_ok()
}

/// Any supported NVIDIA GPU wins, including a hybrid laptop's dGPU next to an Intel or AMD iGPU.
pub fn detect(gpus: &[PciGpu]) -> Flavor {
    if gpus.iter().any(is_nvidia_open_supported) {
        Flavor::Nvidia
    } else {
        Flavor::Default
    }
}

/// `auto`, `nvidia`, `default` (also `mesa`), case-insensitive.
pub fn parse_override(value: &str) -> Option<Override> {
    match value.trim().to_ascii_lowercase().as_str() {
        "auto" => Some(Override::Auto),
        "nvidia" => Some(Override::Flavor(Flavor::Nvidia)),
        "default" | "mesa" => Some(Override::Flavor(Flavor::Default)),
        _ => None,
    }
}

/// The value of the last `wrasse.gpu=` word on a kernel command line.
pub fn cmdline_value(cmdline: &str) -> Option<&str> {
    cmdline.split_whitespace().filter_map(|w| w.strip_prefix("wrasse.gpu=")).next_back()
}

/// An override file holds one word, or `wrasse.gpu=<word>`; blank lines and `#` comments are skipped.
pub fn file_value(contents: &str) -> Option<&str> {
    contents
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| l.strip_prefix("wrasse.gpu=").unwrap_or(l))
}

/// Why a flavor was chosen, for `--explain`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reason {
    Override { source: &'static str, flavor: Flavor },
    NvidiaDetected(PciGpu),
    NoSupportedNvidia { gpus: usize },
}

/// Apply an override (if it is not `auto`), else autodetect.
pub fn resolve(over: Option<(&'static str, Override)>, gpus: &[PciGpu]) -> (Flavor, Reason) {
    if let Some((source, Override::Flavor(flavor))) = over {
        return (flavor, Reason::Override { source, flavor });
    }
    match gpus.iter().find(|g| is_nvidia_open_supported(g)) {
        Some(g) => (Flavor::Nvidia, Reason::NvidiaDetected(*g)),
        None => (Flavor::Default, Reason::NoSupportedNvidia { gpus: gpus.len() }),
    }
}
