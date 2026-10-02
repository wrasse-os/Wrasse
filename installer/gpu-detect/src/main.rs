use std::path::PathBuf;
use std::process::ExitCode;

use wrasse_gpu_detect::{
    cmdline_value, file_value, parse_override, read_gpus, resolve, Override, Reason,
};

const USAGE: &str = "usage: wrasse-gpu-detect [--override auto|nvidia|default] [--sysfs DIR] \
[--cmdline-file FILE] [--override-file FILE] [--explain]

Prints the image name to preselect: wrasse-nvidia for a Turing or newer NVIDIA GPU, else wrasse.
Override precedence: --override, $WRASSE_GPU, wrasse.gpu= on the kernel command line, the override file.";

fn main() -> ExitCode {
    let mut over_arg: Option<String> = None;
    let mut sysfs = PathBuf::from("/sys");
    let mut cmdline_file = PathBuf::from("/proc/cmdline");
    let mut override_file = PathBuf::from("/etc/wrasse/installer-gpu");
    let mut explain = false;

    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut value = |name: &str| {
            args.next().ok_or_else(|| format!("{name} needs a value"))
        };
        let r = match a.as_str() {
            "--override" => value("--override").map(|v| over_arg = Some(v)),
            "--sysfs" => value("--sysfs").map(|v| sysfs = PathBuf::from(v)),
            "--cmdline-file" => value("--cmdline-file").map(|v| cmdline_file = PathBuf::from(v)),
            "--override-file" => value("--override-file").map(|v| override_file = PathBuf::from(v)),
            "--explain" => {
                explain = true;
                Ok(())
            }
            "-h" | "--help" => {
                println!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            other => Err(format!("unknown argument {other}")),
        };
        if let Err(e) = r {
            eprintln!("wrasse-gpu-detect: {e}\n{USAGE}");
            return ExitCode::from(2);
        }
    }

    // First source that holds a valid value wins. An unreadable or invalid one is reported and skipped,
    // so a typo in an override never leaves the installer without a preselection.
    let env_val = std::env::var("WRASSE_GPU").ok();
    let cmdline = std::fs::read_to_string(&cmdline_file).unwrap_or_default();
    let file = std::fs::read_to_string(&override_file).unwrap_or_default();
    let candidates: [(&'static str, Option<String>); 4] = [
        ("--override", over_arg),
        ("WRASSE_GPU", env_val),
        ("kernel command line", cmdline_value(&cmdline).map(str::to_owned)),
        ("override file", file_value(&file).map(str::to_owned)),
    ];
    let mut over: Option<(&'static str, Override)> = None;
    for (source, raw) in candidates {
        let Some(raw) = raw else { continue };
        match parse_override(&raw) {
            Some(o) => {
                over = Some((source, o));
                break;
            }
            None => eprintln!("wrasse-gpu-detect: ignoring invalid {source} value {raw:?} (want auto, nvidia or default)"),
        }
    }

    let gpus = read_gpus(&sysfs);
    let (flavor, reason) = resolve(over, &gpus);
    if explain {
        match reason {
            Reason::Override { source, flavor } => eprintln!("override from {source}: {}", flavor.image_name()),
            Reason::NvidiaDetected(g) => eprintln!("NVIDIA {:04x}:{:04x} is Turing or newer", g.vendor, g.device),
            Reason::NoSupportedNvidia { gpus } => eprintln!("{gpus} display device(s), none a supported NVIDIA GPU"),
        }
    }
    println!("{}", flavor.image_name());
    ExitCode::SUCCESS
}
