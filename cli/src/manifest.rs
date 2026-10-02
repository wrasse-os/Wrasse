//! `~/.config/wrasse/packages.toml`: what the user installed through wrasse, so `wrasse sync`
//! can rebuild it. Also reads the small `config.toml` that holds the Flatpak-vs-brew policy.

use serde::{Deserialize, Serialize};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Backend {
    Flatpak,
    Brew,
    Distrobox,
}

impl fmt::Display for Backend {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Backend::Flatpak => "flatpak",
            Backend::Brew => "brew",
            Backend::Distrobox => "distrobox",
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    /// Flatpak application ID, brew formula, or distro package name.
    pub name: String,
    pub backend: Backend,
    /// Distrobox only: the distro or image given to `--from`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Manifest {
    /// DX sysext switched on through `wrasse install --dx`.
    #[serde(default)]
    pub dx: bool,
    #[serde(default, rename = "package")]
    pub packages: Vec<Entry>,
}

impl Manifest {
    pub fn add(&mut self, entry: Entry) {
        if !self.packages.contains(&entry) {
            self.packages.push(entry);
        }
    }

    pub fn remove(&mut self, entry: &Entry) {
        self.packages.retain(|e| e != entry);
    }
}

/// `$WRASSE_CONFIG_DIR`, else `$XDG_CONFIG_HOME/wrasse`, else `$HOME/.config/wrasse`.
pub fn config_dir() -> Result<PathBuf, String> {
    if let Some(d) = non_empty_env("WRASSE_CONFIG_DIR") {
        return Ok(PathBuf::from(d));
    }
    if let Some(d) = non_empty_env("XDG_CONFIG_HOME") {
        return Ok(PathBuf::from(d).join("wrasse"));
    }
    match non_empty_env("HOME") {
        Some(h) => Ok(PathBuf::from(h).join(".config").join("wrasse")),
        None => Err("cannot find a config directory: HOME is not set".to_string()),
    }
}

fn non_empty_env(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|v| !v.is_empty())
}

/// Where `config.toml` lives, for error messages.
pub fn config_path_hint(dir: &Path) -> String {
    dir.join("config.toml").display().to_string()
}

pub fn manifest_path(dir: &Path) -> PathBuf {
    dir.join("packages.toml")
}

pub fn load(dir: &Path) -> Result<Manifest, String> {
    let path = manifest_path(dir);
    match fs::read_to_string(&path) {
        Ok(text) => {
            toml::from_str(&text).map_err(|e| format!("{} is not valid: {e}", path.display()))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Manifest::default()),
        Err(e) => Err(format!("cannot read {}: {e}", path.display())),
    }
}

pub fn save(dir: &Path, manifest: &Manifest) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    let text = toml::to_string(manifest).map_err(|e| format!("cannot serialize manifest: {e}"))?;
    let path = manifest_path(dir);
    let tmp = dir.join("packages.toml.tmp");
    fs::write(&tmp, text).map_err(|e| format!("cannot write {}: {e}", tmp.display()))?;
    fs::rename(&tmp, &path).map_err(|e| format!("cannot replace {}: {e}", path.display()))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Prefer {
    Flatpak,
    Brew,
    Ask,
}

impl Prefer {
    pub fn parse(s: &str) -> Result<Prefer, String> {
        match s {
            "flatpak" => Ok(Prefer::Flatpak),
            "brew" => Ok(Prefer::Brew),
            "ask" => Ok(Prefer::Ask),
            other => Err(format!(
                "unknown policy '{other}': expected flatpak, brew or ask"
            )),
        }
    }
}

#[derive(Deserialize, Default)]
struct Config {
    prefer: Option<String>,
}

/// The `prefer` policy from `config.toml`. None when unset: there is deliberately no default.
pub fn load_prefer(dir: &Path) -> Result<Option<Prefer>, String> {
    let path = dir.join("config.toml");
    let text = match fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("cannot read {}: {e}", path.display())),
    };
    let cfg: Config =
        toml::from_str(&text).map_err(|e| format!("{} is not valid: {e}", path.display()))?;
    cfg.prefer
        .map(|p| Prefer::parse(&p).map_err(|e| format!("{}: {e}", path.display())))
        .transpose()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmpdir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wrasse-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn missing_file_is_empty() {
        let d = tmpdir("missing");
        assert_eq!(load(&d).unwrap(), Manifest::default());
    }

    #[test]
    fn roundtrip_and_dedupe() {
        let d = tmpdir("roundtrip");
        let mut m = Manifest::default();
        let e = Entry {
            name: "org.mozilla.firefox".into(),
            backend: Backend::Flatpak,
            from: None,
        };
        m.add(e.clone());
        m.add(e.clone());
        m.add(Entry {
            name: "ripgrep".into(),
            backend: Backend::Distrobox,
            from: Some("fedora".into()),
        });
        m.dx = true;
        save(&d, &m).unwrap();
        let back = load(&d).unwrap();
        assert_eq!(back, m);
        assert_eq!(back.packages.len(), 2);
        let text = fs::read_to_string(manifest_path(&d)).unwrap();
        assert!(text.contains("[[package]]"));
        assert!(text.contains("backend = \"flatpak\""));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn remove_entry() {
        let mut m = Manifest::default();
        let e = Entry {
            name: "jq".into(),
            backend: Backend::Brew,
            from: None,
        };
        m.add(e.clone());
        m.remove(&e);
        assert!(m.packages.is_empty());
    }

    #[test]
    fn invalid_manifest_is_an_error() {
        let d = tmpdir("invalid");
        fs::create_dir_all(&d).unwrap();
        fs::write(manifest_path(&d), "package = 3").unwrap();
        assert!(load(&d).is_err());
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn prefer_has_no_default() {
        let d = tmpdir("prefer");
        assert_eq!(load_prefer(&d).unwrap(), None);
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("config.toml"), "prefer = \"brew\"\n").unwrap();
        assert_eq!(load_prefer(&d).unwrap(), Some(Prefer::Brew));
        fs::write(d.join("config.toml"), "prefer = \"nope\"\n").unwrap();
        assert!(load_prefer(&d).is_err());
        fs::remove_dir_all(&d).unwrap();
    }
}
