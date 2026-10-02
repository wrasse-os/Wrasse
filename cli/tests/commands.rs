//! End to end through `app::run` with a fake runner: no real flatpak, brew, distrobox or ujust.

use clap::Parser;
use std::path::PathBuf;
use wrasse::app::{run, Cli, CliError, Ctx, Report};
use wrasse::manifest::{self, Backend};
use wrasse::runner::{Output, Runner};

fn tmpdir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wrasse-it-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

fn go(
    dir: &PathBuf,
    runner: &Runner,
    args: &[&str],
    answer: Option<&str>,
) -> Result<Report, CliError> {
    let mut argv = vec!["wrasse"];
    argv.extend_from_slice(args);
    let cli = Cli::parse_from(argv);
    let ctx = Ctx {
        dir,
        runner,
        json: cli.json,
    };
    let mut ask = |_: &str| answer.map(str::to_string);
    run(&cli, &ctx, &mut ask)
}

const FLATPAK_VLC: &str = "org.videolan.VLC\tVLC\n";
const FLATPAK_BTOP: &str = "io.github.aristocratos.btop\tbtop\n";

#[test]
fn gui_app_goes_to_flatpak_and_is_recorded() {
    let d = tmpdir("gui");
    let r = Runner::fake(vec![
        ("flatpak search", Output::ok(FLATPAK_VLC)),
        ("brew info", Output::fail(1)),
        ("flatpak", Output::ok("")),
    ]);
    let rep = go(&d, &r, &["install", "vlc", "--json"], None).unwrap();
    assert_eq!(rep.data["backend"], "flatpak");
    assert_eq!(rep.data["package"], "org.videolan.VLC");
    let m = manifest::load(&d).unwrap();
    assert_eq!(m.packages.len(), 1);
    assert_eq!(m.packages[0].backend, Backend::Flatpak);
    assert!(r.acted().iter().any(|c| c.contains("install --user")));
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn cli_tool_goes_to_brew() {
    let d = tmpdir("cli");
    let r = Runner::fake(vec![
        ("flatpak search", Output::fail(1)),
        ("brew info", Output::ok("{}")),
        ("brew install", Output::ok("")),
    ]);
    let rep = go(&d, &r, &["install", "ripgrep"], None).unwrap();
    assert_eq!(rep.data["backend"], "brew");
    assert_eq!(r.acted(), vec!["brew install --formula ripgrep"]);
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn both_backends_without_policy_stops_and_installs_nothing() {
    let d = tmpdir("both");
    let r = Runner::fake(vec![
        ("flatpak search", Output::ok(FLATPAK_BTOP)),
        ("brew info", Output::ok("{}")),
    ]);
    let e = go(&d, &r, &["install", "btop"], None).err().unwrap();
    assert_eq!(e.code, "policy_required");
    assert!(e.message.contains("--prefer"));
    assert!(r.acted().is_empty());
    assert!(manifest::load(&d).unwrap().packages.is_empty());
}

#[test]
fn prefer_flag_and_config_file_resolve_it() {
    let d = tmpdir("prefer");
    let rules = || {
        vec![
            ("flatpak search", Output::ok(FLATPAK_BTOP)),
            ("brew info", Output::ok("{}")),
            ("brew install", Output::ok("")),
            ("flatpak", Output::ok("")),
        ]
    };
    let r = Runner::fake(rules());
    let rep = go(&d, &r, &["install", "btop", "--prefer", "brew"], None).unwrap();
    assert_eq!(rep.data["backend"], "brew");

    std::fs::create_dir_all(&d).unwrap();
    std::fs::write(d.join("config.toml"), "prefer = \"flatpak\"\n").unwrap();
    let r = Runner::fake(rules());
    let rep = go(&d, &r, &["install", "btop"], None).unwrap();
    assert_eq!(rep.data["backend"], "flatpak");
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn ask_policy_prompts_or_errors_without_a_terminal() {
    let d = tmpdir("ask");
    let rules = || {
        vec![
            ("flatpak search", Output::ok(FLATPAK_BTOP)),
            ("brew info", Output::ok("{}")),
            ("brew install", Output::ok("")),
        ]
    };
    let r = Runner::fake(rules());
    let rep = go(
        &d,
        &r,
        &["install", "btop", "--prefer", "ask"],
        Some("brew\n"),
    )
    .unwrap();
    assert_eq!(rep.data["backend"], "brew");

    let r = Runner::fake(rules());
    let e = go(&d, &r, &["install", "btop", "--prefer", "ask"], None)
        .err()
        .unwrap();
    assert_eq!(e.code, "needs_terminal");
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn kind_override_needs_no_policy() {
    let d = tmpdir("kind");
    let r = Runner::fake(vec![
        ("flatpak search", Output::ok(FLATPAK_BTOP)),
        ("brew info", Output::ok("{}")),
        ("brew install", Output::ok("")),
    ]);
    let rep = go(&d, &r, &["install", "btop", "--kind", "cli"], None).unwrap();
    assert_eq!(rep.data["backend"], "brew");
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn from_uses_distrobox_and_records_the_distro() {
    let d = tmpdir("from");
    let r = Runner::fake(vec![
        ("distrobox list", Output::ok("ID | NAME\n")),
        ("distrobox", Output::ok("")),
    ]);
    go(&d, &r, &["install", "htop", "--from", "fedora"], None).unwrap();
    let m = manifest::load(&d).unwrap();
    assert_eq!(m.packages[0].backend, Backend::Distrobox);
    assert_eq!(m.packages[0].from.as_deref(), Some("fedora"));
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn dx_toggle_runs_ujust_and_is_recorded() {
    let d = tmpdir("dx");
    let r = Runner::fake(vec![("ujust", Output::ok(""))]);
    go(&d, &r, &["install", "--dx"], None).unwrap();
    assert!(manifest::load(&d).unwrap().dx);
    go(&d, &r, &["remove", "--dx"], None).unwrap();
    assert!(!manifest::load(&d).unwrap().dx);
    assert_eq!(r.acted(), vec!["ujust dx on", "ujust dx off"]);
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn dry_run_changes_nothing_on_disk() {
    let d = tmpdir("dry");
    let r = Runner::dry_run();
    let cli_args = ["--dry-run", "install", "--dx"];
    let rep = go(&d, &r, &cli_args, None).unwrap();
    assert_eq!(rep.data["dry_run"], true);
    assert_eq!(rep.data["commands"][0], "ujust dx on");
    assert!(!d.exists());
}

#[test]
fn remove_runs_backend_and_drops_the_entry() {
    let d = tmpdir("remove");
    let r = Runner::fake(vec![
        ("flatpak search", Output::ok(FLATPAK_VLC)),
        ("brew info", Output::fail(1)),
        ("flatpak", Output::ok("")),
    ]);
    go(&d, &r, &["install", "vlc"], None).unwrap();
    let r = Runner::fake(vec![("flatpak", Output::ok(""))]);
    go(&d, &r, &["remove", "org.videolan.VLC"], None).unwrap();
    assert!(manifest::load(&d).unwrap().packages.is_empty());
    assert!(r.acted()[0].starts_with("flatpak uninstall --user"));

    let e = go(&d, &r, &["remove", "org.videolan.VLC"], None)
        .err()
        .unwrap();
    assert_eq!(e.code, "not_found");
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn failed_install_is_not_recorded() {
    let d = tmpdir("fail");
    let r = Runner::fake(vec![
        ("flatpak search", Output::fail(1)),
        ("brew info", Output::ok("{}")),
        ("brew install", Output::fail(1)),
    ]);
    let e = go(&d, &r, &["install", "broken"], None).err().unwrap();
    assert_eq!(e.code, "backend_failed");
    assert!(manifest::load(&d).unwrap().packages.is_empty());
}

#[test]
fn list_reports_the_manifest() {
    let d = tmpdir("list");
    let r = Runner::fake(vec![
        ("flatpak search", Output::fail(1)),
        ("brew", Output::ok("{}")),
    ]);
    go(&d, &r, &["install", "jq"], None).unwrap();
    let rep = go(&d, &r, &["list", "--json"], None).unwrap();
    assert_eq!(rep.data["packages"][0]["name"], "jq");
    assert_eq!(rep.data["packages"][0]["backend"], "brew");
    assert_eq!(rep.to_json()["ok"], true);
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn search_merges_both_backends_and_tolerates_one_failing() {
    let d = tmpdir("search");
    let r = Runner::fake(vec![
        ("flatpak search", Output::ok("org.videolan.VLC\tVLC\n")),
        ("brew search", Output::ok("==> Formulae\nvlc-tools\n")),
    ]);
    let rep = go(&d, &r, &["search", "vlc"], None).unwrap();
    assert_eq!(rep.data["flatpak"][0]["id"], "org.videolan.VLC");
    assert_eq!(rep.data["brew"][0], "vlc-tools");

    let r = Runner::fake(vec![(
        "flatpak search",
        Output::ok("org.videolan.VLC\tVLC\n"),
    )]);
    let rep = go(&d, &r, &["search", "vlc"], None).unwrap();
    assert_eq!(rep.data["errors"].as_array().unwrap().len(), 1);
}

#[test]
fn sync_installs_only_what_is_missing() {
    let d = tmpdir("sync");
    std::fs::create_dir_all(&d).unwrap();
    std::fs::write(
        manifest::manifest_path(&d),
        r#"
dx = true

[[package]]
name = "org.videolan.VLC"
backend = "flatpak"

[[package]]
name = "jq"
backend = "brew"

[[package]]
name = "htop"
backend = "distrobox"
from = "fedora"
"#,
    )
    .unwrap();
    let r = Runner::fake(vec![
        ("flatpak info", Output::ok("")),
        ("brew list", Output::fail(1)),
        ("brew install", Output::ok("")),
        (
            "distrobox list",
            Output::ok("ID | NAME\n1 | wrasse-fedora\n"),
        ),
        (
            "distrobox enter --name wrasse-fedora -- rpm",
            Output::fail(1),
        ),
        ("distrobox enter", Output::ok("")),
        ("ujust", Output::ok("")),
    ]);
    let rep = go(&d, &r, &["sync", "--json"], None).unwrap();
    assert!(rep.ok);
    assert_eq!(rep.data["already_present"].as_array().unwrap().len(), 1);
    assert_eq!(rep.data["installed"].as_array().unwrap().len(), 2);
    let acted = r.acted();
    assert!(acted.contains(&"brew install --formula jq".to_string()));
    assert!(acted
        .contains(&"distrobox enter --name wrasse-fedora -- sudo dnf install -y htop".to_string()));
    assert!(acted.contains(&"ujust dx on".to_string()));
    assert!(!acted.iter().any(|c| c.starts_with("flatpak install")));
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn sync_reports_partial_failure() {
    let d = tmpdir("syncfail");
    std::fs::create_dir_all(&d).unwrap();
    std::fs::write(
        manifest::manifest_path(&d),
        "[[package]]\nname = \"jq\"\nbackend = \"brew\"\n",
    )
    .unwrap();
    let r = Runner::fake(vec![
        ("brew list", Output::fail(1)),
        ("brew install", Output::fail(1)),
    ]);
    let rep = go(&d, &r, &["sync"], None).unwrap();
    assert!(!rep.ok);
    assert_eq!(rep.to_json()["ok"], false);
    assert_eq!(rep.data["failed"].as_array().unwrap().len(), 1);
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn json_errors_are_machine_readable() {
    let e = CliError {
        code: "policy_required",
        message: "x".into(),
    };
    assert_eq!(e.to_json()["error"]["code"], "policy_required");
    assert_eq!(e.exit_code(), 3);
}
