//! GUI-vs-CLI classification. A Flatpak match means a GUI app, a brew formula match means a
//! CLI tool. When both match, the Flatpak-vs-brew policy decides, and there is no default
//! policy: that is an open decision for the user (SPEC.md, pending decision 1).

use crate::manifest::{Backend, Prefer};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Gui,
    Cli,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlatpakHit {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Choice {
    pub backend: Backend,
    /// Flatpak application ID or brew formula name.
    pub name: String,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClassifyError {
    NotFound,
    /// Several Flatpak apps match the name exactly; the user must pass an application ID.
    AmbiguousFlatpak(Vec<String>),
    /// Exists in both and no policy is set.
    PolicyRequired {
        flatpak_id: String,
    },
    /// Policy is `ask`: the caller must prompt, then call again with a concrete policy.
    Ask {
        flatpak_id: String,
    },
}

/// A Flatpak application ID: three or more dot-separated segments of `[A-Za-z0-9_-]`,
/// e.g. `org.mozilla.firefox`. Brew formula names never look like this.
pub fn looks_like_app_id(s: &str) -> bool {
    let parts: Vec<&str> = s.split('.').collect();
    parts.len() >= 3
        && parts.iter().all(|p| {
            !p.is_empty()
                && p.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        })
}

/// Rows of `flatpak search --columns=application,name` (tab separated) that match `pkg`
/// exactly by application ID, by name, or by the last ID segment, case-insensitively.
/// Duplicates (one row per remote or branch) are collapsed.
pub fn exact_flatpak_matches(pkg: &str, search_output: &str) -> Vec<FlatpakHit> {
    let want = pkg.to_lowercase();
    let mut hits: Vec<FlatpakHit> = Vec::new();
    for line in search_output.lines() {
        let mut cols = line.splitn(2, '\t');
        let id = cols.next().unwrap_or("").trim();
        let name = cols.next().unwrap_or("").trim();
        if id.is_empty() || !looks_like_app_id(id) {
            continue;
        }
        let last = id.rsplit('.').next().unwrap_or("").to_lowercase();
        let matches = id.to_lowercase() == want || name.to_lowercase() == want || last == want;
        if matches && !hits.iter().any(|h| h.id == id) {
            hits.push(FlatpakHit {
                id: id.to_string(),
                name: name.to_string(),
            });
        }
    }
    hits
}

/// Names from `brew search --formula` output: one per line, headers and blanks dropped.
pub fn parse_brew_search(output: &str) -> Vec<String> {
    output
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with("==>"))
        .map(str::to_string)
        .collect()
}

/// Pick a backend. `flatpak_hits` are exact matches only. `brew_found` says the formula exists.
/// `kind` is the user's override (`--kind`); it skips the policy.
pub fn classify(
    pkg: &str,
    kind: Option<Kind>,
    flatpak_hits: &[FlatpakHit],
    brew_found: bool,
    prefer: Option<Prefer>,
) -> Result<Choice, ClassifyError> {
    let want_flatpak = kind != Some(Kind::Cli);
    let want_brew = kind != Some(Kind::Gui);
    let flatpak = if want_flatpak { flatpak_hits } else { &[] };
    let brew = want_brew && brew_found;

    if flatpak.len() > 1 {
        // An exact application ID wins over looser name matches.
        let exact: Vec<&FlatpakHit> = flatpak
            .iter()
            .filter(|h| h.id.eq_ignore_ascii_case(pkg))
            .collect();
        if exact.len() != 1 {
            return Err(ClassifyError::AmbiguousFlatpak(
                flatpak.iter().map(|h| h.id.clone()).collect(),
            ));
        }
        return resolve(pkg, Some(exact[0]), brew, prefer);
    }
    resolve(pkg, flatpak.first(), brew, prefer)
}

fn resolve(
    pkg: &str,
    flatpak: Option<&FlatpakHit>,
    brew: bool,
    prefer: Option<Prefer>,
) -> Result<Choice, ClassifyError> {
    match (flatpak, brew) {
        (None, false) => Err(ClassifyError::NotFound),
        (Some(f), false) => Ok(Choice {
            backend: Backend::Flatpak,
            name: f.id.clone(),
            reason: "found on Flatpak only: GUI app".to_string(),
        }),
        (None, true) => Ok(Choice {
            backend: Backend::Brew,
            name: pkg.to_string(),
            reason: "found as a brew formula only: CLI tool".to_string(),
        }),
        (Some(f), true) => match prefer {
            None => Err(ClassifyError::PolicyRequired {
                flatpak_id: f.id.clone(),
            }),
            Some(Prefer::Ask) => Err(ClassifyError::Ask {
                flatpak_id: f.id.clone(),
            }),
            Some(Prefer::Flatpak) => Ok(Choice {
                backend: Backend::Flatpak,
                name: f.id.clone(),
                reason: "exists in both; policy prefers flatpak".to_string(),
            }),
            Some(Prefer::Brew) => Ok(Choice {
                backend: Backend::Brew,
                name: pkg.to_string(),
                reason: "exists in both; policy prefers brew".to_string(),
            }),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hit(id: &str) -> FlatpakHit {
        FlatpakHit {
            id: id.into(),
            name: String::new(),
        }
    }

    #[test]
    fn app_id_detection() {
        assert!(looks_like_app_id("org.mozilla.firefox"));
        assert!(looks_like_app_id("io.github.some-user.App_1"));
        assert!(!looks_like_app_id("ripgrep"));
        assert!(!looks_like_app_id("python@3.12"));
        assert!(!looks_like_app_id("a.b"));
        assert!(!looks_like_app_id("org..x"));
    }

    #[test]
    fn matches_by_name_id_and_last_segment_without_duplicates() {
        let out = "org.mozilla.firefox\tFirefox\norg.mozilla.firefox\tFirefox\n\
                   dev.other.Fire\tFire Pit\norg.videolan.VLC\tVLC\n";
        assert_eq!(
            exact_flatpak_matches("firefox", out),
            vec![FlatpakHit {
                id: "org.mozilla.firefox".into(),
                name: "Firefox".into()
            }]
        );
        assert_eq!(exact_flatpak_matches("VLC", out).len(), 1);
        assert_eq!(exact_flatpak_matches("org.videolan.vlc", out).len(), 1);
        assert!(exact_flatpak_matches("fir", out).is_empty());
    }

    #[test]
    fn brew_search_drops_headers() {
        assert_eq!(
            parse_brew_search("==> Formulae\nripgrep\n\nripgrep-all\n"),
            vec!["ripgrep", "ripgrep-all"]
        );
    }

    #[test]
    fn single_source_needs_no_policy() {
        let c = classify("vlc", None, &[hit("org.videolan.VLC")], false, None).unwrap();
        assert_eq!(
            (c.backend, c.name.as_str()),
            (Backend::Flatpak, "org.videolan.VLC")
        );
        let c = classify("ripgrep", None, &[], true, None).unwrap();
        assert_eq!((c.backend, c.name.as_str()), (Backend::Brew, "ripgrep"));
        assert_eq!(
            classify("nope", None, &[], false, None),
            Err(ClassifyError::NotFound)
        );
    }

    #[test]
    fn both_without_policy_is_an_error_not_a_default() {
        let r = classify(
            "btop",
            None,
            &[hit("io.github.aristocratos.btop")],
            true,
            None,
        );
        assert!(matches!(r, Err(ClassifyError::PolicyRequired { .. })));
    }

    #[test]
    fn both_with_policy() {
        let h = [hit("io.github.aristocratos.btop")];
        let f = classify("btop", None, &h, true, Some(Prefer::Flatpak)).unwrap();
        assert_eq!(f.backend, Backend::Flatpak);
        let b = classify("btop", None, &h, true, Some(Prefer::Brew)).unwrap();
        assert_eq!((b.backend, b.name.as_str()), (Backend::Brew, "btop"));
        let a = classify("btop", None, &h, true, Some(Prefer::Ask));
        assert!(matches!(a, Err(ClassifyError::Ask { .. })));
    }

    #[test]
    fn kind_override_skips_the_policy() {
        let h = [hit("io.github.aristocratos.btop")];
        let g = classify("btop", Some(Kind::Gui), &h, true, None).unwrap();
        assert_eq!(g.backend, Backend::Flatpak);
        let c = classify("btop", Some(Kind::Cli), &h, true, None).unwrap();
        assert_eq!(c.backend, Backend::Brew);
        assert_eq!(
            classify("btop", Some(Kind::Gui), &[], true, None),
            Err(ClassifyError::NotFound)
        );
    }

    #[test]
    fn several_flatpak_matches_need_an_id() {
        let h = [hit("org.mozilla.firefox"), hit("org.mozilla.Firefox")];
        assert!(matches!(
            classify("firefox", None, &h, false, None),
            Err(ClassifyError::AmbiguousFlatpak(_))
        ));
        let h = [hit("org.a.firefox"), hit("org.b.Firefox")];
        let c = classify("org.a.firefox", None, &h, false, None).unwrap();
        assert_eq!(c.name, "org.a.firefox");
    }
}
