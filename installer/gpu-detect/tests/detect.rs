use std::fs;
use std::path::Path;
use std::process::Command;

use wrasse_gpu_detect::*;

fn add_dev(root: &Path, addr: &str, vendor: &str, device: &str, class: &str) {
    let d = root.join("bus/pci/devices").join(addr);
    fs::create_dir_all(&d).unwrap();
    fs::write(d.join("vendor"), format!("{vendor}\n")).unwrap();
    fs::write(d.join("device"), format!("{device}\n")).unwrap();
    fs::write(d.join("class"), format!("{class}\n")).unwrap();
}

fn tmp(name: &str) -> std::path::PathBuf {
    let p = std::env::temp_dir().join(format!("wrasse-gpu-detect-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&p);
    fs::create_dir_all(&p).unwrap();
    p
}

fn gpu(vendor: u16, device: u16) -> PciGpu {
    PciGpu { vendor, device }
}

#[test]
fn id_table_is_sorted_unique_and_big_enough() {
    assert!(NVIDIA_OPEN_DEVICE_IDS.len() > 200);
    assert!(NVIDIA_OPEN_DEVICE_IDS.windows(2).all(|w| w[0] < w[1]));
}

#[test]
fn turing_ampere_ada_blackwell_are_supported() {
    for id in [0x1E04, 0x1F82, 0x2182, 0x2204, 0x2684, 0x2B85] {
        assert!(is_nvidia_open_supported(&gpu(0x10de, id)), "{id:04x}");
    }
}

#[test]
fn pascal_and_maxwell_are_not_supported() {
    // GTX 1080 (GP104), GT 1030 (GP108), GTX 980 (GM204)
    for id in [0x1B80, 0x1D01, 0x13C0] {
        assert!(!is_nvidia_open_supported(&gpu(0x10de, id)), "{id:04x}");
    }
}

#[test]
fn same_device_id_from_another_vendor_is_not_nvidia() {
    assert!(!is_nvidia_open_supported(&gpu(0x1002, 0x2684)));
}

#[test]
fn detect_prefers_nvidia_in_a_hybrid_laptop() {
    assert_eq!(detect(&[gpu(0x8086, 0x9a49), gpu(0x10de, 0x2520)]), Flavor::Nvidia);
}

#[test]
fn detect_defaults_without_a_supported_nvidia() {
    assert_eq!(detect(&[]), Flavor::Default);
    assert_eq!(detect(&[gpu(0x1002, 0x744c)]), Flavor::Default);
    assert_eq!(detect(&[gpu(0x10de, 0x1B80)]), Flavor::Default);
}

#[test]
fn image_names_follow_the_spec() {
    assert_eq!(Flavor::Default.image_name(), "wrasse");
    assert_eq!(Flavor::Nvidia.image_name(), "wrasse-nvidia");
}

#[test]
fn read_gpus_keeps_display_classes_and_skips_the_hdmi_audio_function() {
    let root = tmp("sysfs");
    add_dev(&root, "0000:00:02.0", "0x8086", "0x9a49", "0x030000");
    add_dev(&root, "0000:01:00.0", "0x10de", "0x2684", "0x030200"); // 3D controller
    add_dev(&root, "0000:01:00.1", "0x10de", "0x22ba", "0x040300"); // audio
    add_dev(&root, "0000:00:14.0", "0x8086", "0x43ed", "0x0c0330"); // USB
    let gpus = read_gpus(&root);
    assert_eq!(gpus, vec![gpu(0x10de, 0x2684), gpu(0x8086, 0x9a49)]); // sorted by vendor
    fs::remove_dir_all(&root).unwrap();
}

#[test]
fn read_gpus_on_a_missing_sysfs_is_empty() {
    assert!(read_gpus(Path::new("/nonexistent/wrasse")).is_empty());
}

#[test]
fn override_words() {
    assert_eq!(parse_override("nvidia"), Some(Override::Flavor(Flavor::Nvidia)));
    assert_eq!(parse_override(" Default\n"), Some(Override::Flavor(Flavor::Default)));
    assert_eq!(parse_override("mesa"), Some(Override::Flavor(Flavor::Default)));
    assert_eq!(parse_override("auto"), Some(Override::Auto));
    assert_eq!(parse_override("amd"), None);
}

#[test]
fn cmdline_takes_the_last_wrasse_gpu_word() {
    assert_eq!(cmdline_value("quiet rd.live.image wrasse.gpu=default wrasse.gpu=nvidia"), Some("nvidia"));
    assert_eq!(cmdline_value("quiet nowrasse.gpu=nvidia"), None);
}

#[test]
fn override_file_skips_comments_and_accepts_the_cmdline_spelling() {
    assert_eq!(file_value("# comment\n\nnvidia\n"), Some("nvidia"));
    assert_eq!(file_value("wrasse.gpu=default"), Some("default"));
    assert_eq!(file_value("# only a comment\n"), None);
}

#[test]
fn resolve_override_beats_hardware_but_auto_does_not() {
    let nv = [gpu(0x10de, 0x2684)];
    let (f, _) = resolve(Some(("test", Override::Flavor(Flavor::Default))), &nv);
    assert_eq!(f, Flavor::Default);
    let (f, r) = resolve(Some(("test", Override::Auto)), &nv);
    assert_eq!(f, Flavor::Nvidia);
    assert_eq!(r, Reason::NvidiaDetected(nv[0]));
}

fn run(root: &Path, extra: &[&str], env: Option<&str>) -> (String, String) {
    let mut c = Command::new(env!("CARGO_BIN_EXE_wrasse-gpu-detect"));
    c.arg("--sysfs").arg(root);
    c.arg("--cmdline-file").arg(root.join("cmdline"));
    c.arg("--override-file").arg(root.join("override"));
    c.args(extra).env_remove("WRASSE_GPU");
    if let Some(v) = env {
        c.env("WRASSE_GPU", v);
    }
    let out = c.output().unwrap();
    assert!(out.status.success());
    (
        String::from_utf8(out.stdout).unwrap().trim().to_owned(),
        String::from_utf8(out.stderr).unwrap(),
    )
}

#[test]
fn binary_autodetects_and_honors_override_precedence() {
    let root = tmp("bin");
    add_dev(&root, "0000:01:00.0", "0x10de", "0x2684", "0x030000");
    fs::write(root.join("cmdline"), "quiet wrasse.gpu=default\n").unwrap();
    fs::write(root.join("override"), "nvidia\n").unwrap();

    // cmdline beats the file
    assert_eq!(run(&root, &[], None).0, "wrasse");
    // env beats cmdline
    assert_eq!(run(&root, &[], Some("nvidia")).0, "wrasse-nvidia");
    // flag beats env
    assert_eq!(run(&root, &["--override", "default"], Some("nvidia")).0, "wrasse");
    // "auto" falls through to hardware
    assert_eq!(run(&root, &["--override", "auto"], None).0, "wrasse-nvidia");
    fs::remove_dir_all(&root).unwrap();
}

#[test]
fn binary_ignores_a_bad_override_and_still_answers() {
    let root = tmp("bad");
    add_dev(&root, "0000:00:02.0", "0x8086", "0x9a49", "0x030000");
    let (out, err) = run(&root, &["--override", "banana", "--explain"], None);
    assert_eq!(out, "wrasse");
    assert!(err.contains("invalid"));
    fs::remove_dir_all(&root).unwrap();
}
