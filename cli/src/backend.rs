//! Direct functions over each backend's own CLI. wrasse routes; flatpak, brew, distrobox and
//! ujust do the real work. Every function takes the `Runner` so tests never touch real tools.

use crate::classify::{exact_flatpak_matches, parse_brew_search, FlatpakHit};
use crate::runner::{Output, Runner};

const FLATHUB_URL: &str = "https://dl.flathub.org/repo/flathub.flatpakrepo";

/// Turn a finished command into `Ok(output)` or an error naming the command.
pub fn check(what: &str, out: Output) -> Result<Output, String> {
    if out.success() {
        Ok(out)
    } else {
        let detail = out.stderr.trim();
        if detail.is_empty() {
            Err(format!("{what} failed (exit {})", out.code))
        } else {
            Err(format!("{what} failed (exit {}): {detail}", out.code))
        }
    }
}

// ---- flatpak ----

pub fn flatpak_search(r: &Runner, query: &str) -> Result<Vec<(String, String)>, String> {
    let out = r.query("flatpak", &["search", "--columns=application,name", query])?;
    // flatpak exits non-zero with no rows when nothing matches.
    if !out.success() && out.stdout.trim().is_empty() {
        return Ok(Vec::new());
    }
    let out = check("flatpak search", out)?;
    Ok(out
        .stdout
        .lines()
        .filter_map(|l| {
            let mut c = l.splitn(2, '\t');
            let id = c.next()?.trim();
            let name = c.next().unwrap_or("").trim();
            (!id.is_empty()).then(|| (id.to_string(), name.to_string()))
        })
        .collect())
}

pub fn flatpak_exact(r: &Runner, pkg: &str) -> Result<Vec<FlatpakHit>, String> {
    let out = r.query("flatpak", &["search", "--columns=application,name", pkg])?;
    if !out.success() && out.stdout.trim().is_empty() {
        return Ok(Vec::new());
    }
    let out = check("flatpak search", out)?;
    Ok(exact_flatpak_matches(pkg, &out.stdout))
}

pub fn flatpak_install(r: &Runner, id: &str, stream: bool) -> Result<Output, String> {
    check(
        "flatpak remote-add",
        r.act(
            "flatpak",
            &[
                "remote-add",
                "--user",
                "--if-not-exists",
                "flathub",
                FLATHUB_URL,
            ],
            stream,
        )?,
    )?;
    check(
        "flatpak install",
        r.act(
            "flatpak",
            &[
                "install",
                "--user",
                "--assumeyes",
                "--noninteractive",
                "flathub",
                id,
            ],
            stream,
        )?,
    )
}

pub fn flatpak_remove(r: &Runner, id: &str, stream: bool) -> Result<Output, String> {
    check(
        "flatpak uninstall",
        r.act(
            "flatpak",
            &["uninstall", "--user", "--assumeyes", "--noninteractive", id],
            stream,
        )?,
    )
}

pub fn flatpak_installed(r: &Runner, id: &str) -> Result<bool, String> {
    Ok(r.query("flatpak", &["info", "--user", id])?.success())
}

// ---- brew ----

pub fn brew_search(r: &Runner, query: &str) -> Result<Vec<String>, String> {
    let out = r.query("brew", &["search", "--formula", query])?;
    if !out.success() && out.stdout.trim().is_empty() {
        return Ok(Vec::new());
    }
    Ok(parse_brew_search(&check("brew search", out)?.stdout))
}

pub fn brew_has_formula(r: &Runner, pkg: &str) -> Result<bool, String> {
    Ok(r.query("brew", &["info", "--formula", "--json=v2", pkg])?
        .success())
}

pub fn brew_install(r: &Runner, pkg: &str, stream: bool) -> Result<Output, String> {
    check(
        "brew install",
        r.act("brew", &["install", "--formula", pkg], stream)?,
    )
}

pub fn brew_remove(r: &Runner, pkg: &str, stream: bool) -> Result<Output, String> {
    check(
        "brew uninstall",
        r.act("brew", &["uninstall", "--formula", pkg], stream)?,
    )
}

pub fn brew_installed(r: &Runner, pkg: &str) -> Result<bool, String> {
    Ok(r.query("brew", &["list", "--formula", pkg])?.success())
}

// ---- distrobox ----

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Family {
    Dnf,
    Apt,
    Pacman,
    Apk,
    Zypper,
}

/// Container image for a distro name. A full image reference (has `/` or `:`) is used as is.
pub fn distro_image(from: &str) -> Result<String, String> {
    if from.contains('/') || from.contains(':') {
        return Ok(from.to_string());
    }
    let image = match from {
        "fedora" => "registry.fedoraproject.org/fedora-toolbox:latest",
        "ubuntu" => "docker.io/library/ubuntu:latest",
        "debian" => "docker.io/library/debian:stable",
        "arch" | "archlinux" => "docker.io/library/archlinux:latest",
        "alpine" => "docker.io/library/alpine:latest",
        "opensuse" | "tumbleweed" => "registry.opensuse.org/opensuse/distrobox:latest",
        other => {
            return Err(format!(
                "unknown distro '{other}': use fedora, ubuntu, debian, arch, alpine, opensuse, \
                 or a full image reference such as quay.io/fedora/fedora:43"
            ))
        }
    };
    Ok(image.to_string())
}

fn family(image: &str) -> Result<Family, String> {
    let i = image.to_lowercase();
    let has = |words: &[&str]| words.iter().any(|w| i.contains(w));
    if has(&["fedora", "centos", "rhel", "alma", "rocky"]) {
        Ok(Family::Dnf)
    } else if has(&["ubuntu", "debian"]) {
        Ok(Family::Apt)
    } else if has(&["arch"]) {
        Ok(Family::Pacman)
    } else if has(&["alpine"]) {
        Ok(Family::Apk)
    } else if has(&["suse"]) {
        Ok(Family::Zypper)
    } else {
        Err(format!(
            "cannot tell which package manager '{image}' uses; use fedora, ubuntu, debian, arch, \
             alpine or opensuse"
        ))
    }
}

/// Stable container name for a distro: `wrasse-fedora`, `wrasse-quay-io-fedora-fedora-43`.
pub fn container_name(from: &str) -> String {
    let mut name = String::from("wrasse-");
    let mut last_dash = true;
    for c in from.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            name.push(c);
            last_dash = false;
        } else if !last_dash {
            name.push('-');
            last_dash = true;
        }
    }
    name.trim_end_matches('-').to_string()
}

fn install_steps(fam: Family, pkg: &str) -> Vec<Vec<String>> {
    let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
    let with = |mut v: Vec<String>| {
        v.push(pkg.to_string());
        v
    };
    match fam {
        Family::Dnf => vec![with(s(&["sudo", "dnf", "install", "-y"]))],
        Family::Apt => vec![
            s(&["sudo", "apt-get", "update"]),
            with(s(&["sudo", "apt-get", "install", "-y"])),
        ],
        Family::Pacman => vec![with(s(&[
            "sudo",
            "pacman",
            "-Syu",
            "--noconfirm",
            "--needed",
        ]))],
        Family::Apk => vec![with(s(&["sudo", "apk", "add"]))],
        Family::Zypper => vec![with(s(&["sudo", "zypper", "--non-interactive", "install"]))],
    }
}

fn remove_cmd(fam: Family, pkg: &str) -> Vec<String> {
    let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
    let mut v = match fam {
        Family::Dnf => s(&["sudo", "dnf", "remove", "-y"]),
        Family::Apt => s(&["sudo", "apt-get", "remove", "-y"]),
        Family::Pacman => s(&["sudo", "pacman", "-Rs", "--noconfirm"]),
        Family::Apk => s(&["sudo", "apk", "del"]),
        Family::Zypper => s(&["sudo", "zypper", "--non-interactive", "remove"]),
    };
    v.push(pkg.to_string());
    v
}

fn query_cmd(fam: Family, pkg: &str) -> Vec<String> {
    let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
    let mut v = match fam {
        Family::Dnf | Family::Zypper => s(&["rpm", "-q"]),
        Family::Apt => s(&["dpkg", "-s"]),
        Family::Pacman => s(&["pacman", "-Q"]),
        Family::Apk => s(&["apk", "info", "-e"]),
    };
    v.push(pkg.to_string());
    v
}

fn enter<'a>(name: &'a str, cmd: &'a [String]) -> Vec<&'a str> {
    let mut args = vec!["enter", "--name", name, "--"];
    args.extend(cmd.iter().map(String::as_str));
    args
}

pub fn distrobox_container_exists(r: &Runner, name: &str) -> Result<bool, String> {
    let out = check(
        "distrobox list",
        r.query("distrobox", &["list", "--no-color"])?,
    )?;
    Ok(out
        .stdout
        .lines()
        .skip(1)
        .any(|l| l.split('|').nth(1).map(str::trim) == Some(name)))
}

pub fn distrobox_install(
    r: &Runner,
    from: &str,
    pkg: &str,
    stream: bool,
) -> Result<Output, String> {
    let image = distro_image(from)?;
    let fam = family(&image)?;
    let name = container_name(from);
    if !distrobox_container_exists(r, &name)? {
        check(
            "distrobox create",
            r.act(
                "distrobox",
                &["create", "--yes", "--name", &name, "--image", &image],
                stream,
            )?,
        )?;
    }
    let mut last = Output::ok("");
    for step in install_steps(fam, pkg) {
        last = check(
            "distrobox enter",
            r.act("distrobox", &enter(&name, &step), stream)?,
        )?;
    }
    Ok(last)
}

pub fn distrobox_remove(r: &Runner, from: &str, pkg: &str, stream: bool) -> Result<Output, String> {
    let fam = family(&distro_image(from)?)?;
    let name = container_name(from);
    let cmd = remove_cmd(fam, pkg);
    check(
        "distrobox enter",
        r.act("distrobox", &enter(&name, &cmd), stream)?,
    )
}

pub fn distrobox_installed(r: &Runner, from: &str, pkg: &str) -> Result<bool, String> {
    let fam = family(&distro_image(from)?)?;
    let name = container_name(from);
    if !distrobox_container_exists(r, &name)? {
        return Ok(false);
    }
    let cmd = query_cmd(fam, pkg);
    Ok(r.query("distrobox", &enter(&name, &cmd))?.success())
}

// ---- DX toggle ----

pub fn dx_toggle(r: &Runner, on: bool, stream: bool) -> Result<Output, String> {
    let state = if on { "on" } else { "off" };
    check("ujust dx", r.act("ujust", &["dx", state], stream)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn container_names_are_stable() {
        assert_eq!(container_name("fedora"), "wrasse-fedora");
        assert_eq!(
            container_name("quay.io/fedora/fedora:43"),
            "wrasse-quay-io-fedora-fedora-43"
        );
    }

    #[test]
    fn images_and_families() {
        assert_eq!(
            distro_image("ubuntu").unwrap(),
            "docker.io/library/ubuntu:latest"
        );
        assert_eq!(
            distro_image("quay.io/fedora/fedora:43").unwrap(),
            "quay.io/fedora/fedora:43"
        );
        assert!(distro_image("gentoo").is_err());
        assert_eq!(family("quay.io/fedora/fedora:43").unwrap(), Family::Dnf);
        assert_eq!(
            family("docker.io/library/archlinux:latest").unwrap(),
            Family::Pacman
        );
        assert!(family("example.com/unknown:1").is_err());
    }

    #[test]
    fn flatpak_search_treats_no_match_as_empty() {
        let r = Runner::fake(vec![("flatpak search", Output::fail(1))]);
        assert!(flatpak_search(&r, "zzz").unwrap().is_empty());
    }

    #[test]
    fn flatpak_install_adds_remote_then_installs() {
        let r = Runner::fake(vec![("flatpak", Output::ok(""))]);
        flatpak_install(&r, "org.videolan.VLC", false).unwrap();
        let acted = r.acted();
        assert_eq!(acted.len(), 2);
        assert!(acted[0].starts_with("flatpak remote-add --user --if-not-exists flathub"));
        assert_eq!(
            acted[1],
            "flatpak install --user --assumeyes --noninteractive flathub org.videolan.VLC"
        );
    }

    #[test]
    fn failure_surfaces_stderr() {
        let r = Runner::fake(vec![(
            "brew install",
            Output {
                code: 1,
                stdout: String::new(),
                stderr: "Error: boom\n".into(),
            },
        )]);
        let e = brew_install(&r, "x", false).unwrap_err();
        assert!(e.contains("brew install failed (exit 1): Error: boom"));
    }

    #[test]
    fn distrobox_creates_container_when_missing() {
        let list = "ID | NAME | STATUS | IMAGE\n1 | other | Up | x\n";
        let r = Runner::fake(vec![
            ("distrobox list", Output::ok(list)),
            ("distrobox create", Output::ok("")),
            ("distrobox enter", Output::ok("")),
        ]);
        distrobox_install(&r, "ubuntu", "ripgrep", false).unwrap();
        assert_eq!(
            r.acted(),
            vec![
                "distrobox create --yes --name wrasse-ubuntu --image docker.io/library/ubuntu:latest",
                "distrobox enter --name wrasse-ubuntu -- sudo apt-get update",
                "distrobox enter --name wrasse-ubuntu -- sudo apt-get install -y ripgrep",
            ]
        );
    }

    #[test]
    fn distrobox_reuses_existing_container() {
        let list = "ID | NAME | STATUS | IMAGE\n1 | wrasse-fedora | Up | x\n";
        let r = Runner::fake(vec![
            ("distrobox list", Output::ok(list)),
            ("distrobox enter", Output::ok("")),
        ]);
        distrobox_install(&r, "fedora", "htop", false).unwrap();
        assert_eq!(
            r.acted(),
            vec!["distrobox enter --name wrasse-fedora -- sudo dnf install -y htop"]
        );
    }

    #[test]
    fn dx_toggle_calls_ujust() {
        let r = Runner::fake(vec![("ujust", Output::ok(""))]);
        dx_toggle(&r, true, true).unwrap();
        dx_toggle(&r, false, true).unwrap();
        assert_eq!(r.acted(), vec!["ujust dx on", "ujust dx off"]);
    }
}
