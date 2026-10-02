//! Command parsing and the five commands. Each command returns a `Report` holding both the
//! JSON value (for `--json`) and the human text, so the two outputs cannot drift apart.

use crate::backend;
use crate::classify::{classify, looks_like_app_id, Choice, ClassifyError, Kind};
use crate::manifest::{self, Backend, Entry, Manifest, Prefer};
use crate::runner::Runner;
use clap::{Args, Parser, Subcommand, ValueEnum};
use serde_json::{json, Value};
use std::path::Path;

#[derive(Parser, Debug)]
#[command(
    name = "wrasse",
    version,
    about = "Install software the Wrasse way: a router over Flatpak, brew, distrobox and the DX toggle"
)]
pub struct Cli {
    /// Print one JSON object on stdout instead of text (errors too).
    #[arg(long, global = true)]
    pub json: bool,
    /// Show what would run without changing anything (lookups still run).
    #[arg(long, global = true)]
    pub dry_run: bool,
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Install a package, or switch the DX sysext on with --dx.
    Install(InstallArgs),
    /// Remove a package that wrasse installed, or switch DX off with --dx.
    Remove(RemoveArgs),
    /// List what wrasse has recorded in packages.toml.
    List,
    /// Search Flatpak and brew.
    Search(SearchArgs),
    /// Install everything in packages.toml that is missing on this machine.
    Sync,
}

#[derive(Args, Debug)]
pub struct InstallArgs {
    /// Package name, Flatpak application ID, or brew formula.
    #[arg(required_unless_present = "dx", conflicts_with = "dx")]
    pub package: Option<String>,
    /// Install inside a distrobox container for this distro or image instead.
    #[arg(long, value_name = "DISTRO", conflicts_with = "dx")]
    pub from: Option<String>,
    /// Run `ujust dx on` instead of installing a package.
    #[arg(long)]
    pub dx: bool,
    /// Skip classification: gui means Flatpak, cli means brew.
    #[arg(long, value_enum)]
    pub kind: Option<KindArg>,
    /// What to do when a package exists as both Flatpak and brew. No default: if unset here
    /// and in config.toml, wrasse stops and asks you to choose.
    #[arg(long, value_enum)]
    pub prefer: Option<PreferArg>,
}

#[derive(Args, Debug)]
pub struct RemoveArgs {
    #[arg(required_unless_present = "dx", conflicts_with = "dx")]
    pub package: Option<String>,
    /// Only the entry installed with this backend, when a name is in several.
    #[arg(long, value_enum, conflicts_with = "dx")]
    pub backend: Option<BackendArg>,
    /// Only the distrobox entry installed from this distro.
    #[arg(long, value_name = "DISTRO", conflicts_with = "dx")]
    pub from: Option<String>,
    /// Run `ujust dx off` instead of removing a package.
    #[arg(long)]
    pub dx: bool,
}

#[derive(Args, Debug)]
pub struct SearchArgs {
    pub query: String,
    /// Most results per backend.
    #[arg(long, default_value_t = 25)]
    pub limit: usize,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
pub enum KindArg {
    Gui,
    Cli,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
pub enum PreferArg {
    Flatpak,
    Brew,
    Ask,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
pub enum BackendArg {
    Flatpak,
    Brew,
    Distrobox,
}

impl From<BackendArg> for Backend {
    fn from(b: BackendArg) -> Backend {
        match b {
            BackendArg::Flatpak => Backend::Flatpak,
            BackendArg::Brew => Backend::Brew,
            BackendArg::Distrobox => Backend::Distrobox,
        }
    }
}

#[derive(Debug)]
pub struct CliError {
    /// Stable machine-readable code for agents.
    pub code: &'static str,
    pub message: String,
}

impl CliError {
    fn new(code: &'static str, message: impl Into<String>) -> CliError {
        CliError {
            code,
            message: message.into(),
        }
    }

    pub fn exit_code(&self) -> i32 {
        match self.code {
            "policy_required" | "needs_terminal" => 3,
            _ => 1,
        }
    }

    pub fn to_json(&self) -> Value {
        json!({ "ok": false, "error": { "code": self.code, "message": self.message } })
    }
}

fn backend_err(e: String) -> CliError {
    CliError::new("backend_failed", e)
}

pub struct Report {
    pub data: Value,
    pub text: String,
    /// False when the command ran but part of it failed (`sync`); the exit code is then 1.
    pub ok: bool,
}

impl Report {
    pub fn to_json(&self) -> Value {
        json!({ "ok": self.ok, "result": self.data })
    }
}

pub struct Ctx<'a> {
    pub dir: &'a Path,
    pub runner: &'a Runner,
    pub json: bool,
}

impl Ctx<'_> {
    /// Child output goes straight to the terminal unless a JSON document is being printed.
    fn stream(&self) -> bool {
        !self.json
    }

    fn dry(&self) -> bool {
        self.runner.is_dry_run()
    }

    fn load(&self) -> Result<Manifest, CliError> {
        manifest::load(self.dir).map_err(|e| CliError::new("manifest", e))
    }

    fn save(&self, m: &Manifest) -> Result<(), CliError> {
        if self.dry() {
            return Ok(());
        }
        manifest::save(self.dir, m).map_err(|e| CliError::new("manifest", e))
    }
}

/// `ask` shows a question and returns the answer, or None when there is nobody to ask.
pub fn run(
    cli: &Cli,
    ctx: &Ctx,
    ask: &mut dyn FnMut(&str) -> Option<String>,
) -> Result<Report, CliError> {
    match &cli.command {
        Command::Install(a) => install(ctx, a, ask),
        Command::Remove(a) => remove(ctx, a),
        Command::List => list(ctx),
        Command::Search(a) => search(ctx, a),
        Command::Sync => sync(ctx),
    }
}

fn planned(ctx: &Ctx) -> Value {
    json!(ctx.runner.acted())
}

fn install(
    ctx: &Ctx,
    a: &InstallArgs,
    ask: &mut dyn FnMut(&str) -> Option<String>,
) -> Result<Report, CliError> {
    let mut m = ctx.load()?;
    if a.dx {
        backend::dx_toggle(ctx.runner, true, ctx.stream()).map_err(backend_err)?;
        m.dx = true;
        ctx.save(&m)?;
        return Ok(Report {
            data: json!({ "action": "install", "dx": true, "dry_run": ctx.dry(), "commands": planned(ctx) }),
            text: done_text(ctx, "DX sysext is on"),
            ok: true,
        });
    }
    let pkg = a.package.as_deref().unwrap_or_default();

    let (entry, reason) = if let Some(from) = &a.from {
        backend::distrobox_install(ctx.runner, from, pkg, ctx.stream()).map_err(backend_err)?;
        (
            Entry {
                name: pkg.to_string(),
                backend: Backend::Distrobox,
                from: Some(from.clone()),
            },
            format!("installed in distrobox container for '{from}'"),
        )
    } else {
        let kind = a.kind.map(|k| match k {
            KindArg::Gui => Kind::Gui,
            KindArg::Cli => Kind::Cli,
        });
        let prefer = match a.prefer {
            Some(p) => Some(match p {
                PreferArg::Flatpak => Prefer::Flatpak,
                PreferArg::Brew => Prefer::Brew,
                PreferArg::Ask => Prefer::Ask,
            }),
            None => manifest::load_prefer(ctx.dir).map_err(|e| CliError::new("config", e))?,
        };
        let choice = route(ctx, pkg, kind, prefer, ask)?;
        match choice.backend {
            Backend::Flatpak => backend::flatpak_install(ctx.runner, &choice.name, ctx.stream())
                .map_err(backend_err)?,
            Backend::Brew => backend::brew_install(ctx.runner, &choice.name, ctx.stream())
                .map_err(backend_err)?,
            Backend::Distrobox => unreachable!("route never picks distrobox"),
        };
        (
            Entry {
                name: choice.name,
                backend: choice.backend,
                from: None,
            },
            choice.reason,
        )
    };

    m.add(entry.clone());
    ctx.save(&m)?;
    let text = done_text(
        ctx,
        &format!("installed {} with {} ({reason})", entry.name, entry.backend),
    );
    Ok(Report {
        data: json!({
            "action": "install",
            "package": entry.name,
            "backend": entry.backend,
            "from": entry.from,
            "reason": reason,
            "dry_run": ctx.dry(),
            "commands": planned(ctx),
        }),
        text,
        ok: true,
    })
}

fn done_text(ctx: &Ctx, msg: &str) -> String {
    if ctx.dry() {
        let mut t = format!("dry run, nothing changed. Would have: {msg}\n");
        for c in ctx.runner.acted() {
            t.push_str(&format!("  {c}\n"));
        }
        t.trim_end().to_string()
    } else {
        msg.to_string()
    }
}

/// Look the package up in Flatpak and brew, then classify. A backend whose tool is missing or
/// fails to answer counts as "not found there"; that error is only reported if nothing else matched.
fn route(
    ctx: &Ctx,
    pkg: &str,
    kind: Option<Kind>,
    prefer: Option<Prefer>,
    ask: &mut dyn FnMut(&str) -> Option<String>,
) -> Result<Choice, CliError> {
    let mut lookup_error: Option<String> = None;

    let flatpak_hits = if kind == Some(Kind::Cli) {
        Vec::new()
    } else {
        backend::flatpak_exact(ctx.runner, pkg).unwrap_or_else(|e| {
            lookup_error.get_or_insert(e);
            Vec::new()
        })
    };
    let brew_found = if kind == Some(Kind::Gui) || looks_like_app_id(pkg) {
        false
    } else {
        backend::brew_has_formula(ctx.runner, pkg).unwrap_or_else(|e| {
            lookup_error.get_or_insert(e);
            false
        })
    };

    match classify(pkg, kind, &flatpak_hits, brew_found, prefer) {
        Ok(c) => Ok(c),
        Err(ClassifyError::NotFound) => Err(match lookup_error {
            Some(e) => backend_err(e),
            None => CliError::new(
                "not_found",
                format!("'{pkg}' was not found on Flatpak or in brew; try `wrasse search {pkg}`"),
            ),
        }),
        Err(ClassifyError::AmbiguousFlatpak(ids)) => Err(CliError::new(
            "ambiguous",
            format!(
                "'{pkg}' matches several Flatpak apps: {}. Pass the exact application ID.",
                ids.join(", ")
            ),
        )),
        Err(ClassifyError::PolicyRequired { flatpak_id }) => Err(CliError::new(
            "policy_required",
            format!(
                "'{pkg}' exists as both a Flatpak app ({flatpak_id}) and a brew formula, and no \
                 policy is set. Pass --prefer flatpak|brew|ask, set `prefer = \"flatpak\"` (or \
                 \"brew\" or \"ask\") in {}, or force one with --kind gui|cli.",
                manifest::config_path_hint(ctx.dir)
            ),
        )),
        Err(ClassifyError::Ask { flatpak_id }) => {
            let question = format!(
                "'{pkg}' exists as a Flatpak app ({flatpak_id}) and as a brew formula. Install which? [flatpak/brew] "
            );
            let answer = ask(&question).ok_or_else(|| {
                CliError::new(
                    "needs_terminal",
                    format!(
                        "'{pkg}' exists in both Flatpak and brew and the policy is `ask`, but \
                         there is no terminal to ask on. Pass --prefer flatpak or --prefer brew."
                    ),
                )
            })?;
            let chosen = match Prefer::parse(answer.trim()) {
                Ok(p @ (Prefer::Flatpak | Prefer::Brew)) => p,
                _ => {
                    return Err(CliError::new(
                        "needs_terminal",
                        "answer must be 'flatpak' or 'brew'",
                    ))
                }
            };
            classify(pkg, kind, &flatpak_hits, brew_found, Some(chosen))
                .map_err(|_| CliError::new("not_found", format!("'{pkg}' not found")))
        }
    }
}

fn remove(ctx: &Ctx, a: &RemoveArgs) -> Result<Report, CliError> {
    let mut m = ctx.load()?;
    if a.dx {
        backend::dx_toggle(ctx.runner, false, ctx.stream()).map_err(backend_err)?;
        m.dx = false;
        ctx.save(&m)?;
        return Ok(Report {
            data: json!({ "action": "remove", "dx": false, "dry_run": ctx.dry(), "commands": planned(ctx) }),
            text: done_text(ctx, "DX sysext is off"),
            ok: true,
        });
    }
    let pkg = a.package.as_deref().unwrap_or_default();
    let wanted_backend: Option<Backend> = a.backend.map(Into::into);
    let matches: Vec<Entry> = m
        .packages
        .iter()
        .filter(|e| {
            e.name == pkg
                && wanted_backend.is_none_or(|b| e.backend == b)
                && a.from.as_ref().is_none_or(|f| e.from.as_ref() == Some(f))
        })
        .cloned()
        .collect();
    let entry = match matches.as_slice() {
        [] => {
            return Err(CliError::new(
                "not_found",
                format!(
                    "'{pkg}' is not in packages.toml; run `wrasse list` to see what wrasse manages"
                ),
            ))
        }
        [one] => one.clone(),
        many => {
            let which: Vec<String> = many
                .iter()
                .map(|e| match &e.from {
                    Some(f) => format!("{} (from {f})", e.backend),
                    None => e.backend.to_string(),
                })
                .collect();
            return Err(CliError::new(
                "ambiguous",
                format!(
                    "'{pkg}' is recorded for several backends: {}. Pass --backend, and --from for distrobox.",
                    which.join(", ")
                ),
            ));
        }
    };
    match entry.backend {
        Backend::Flatpak => backend::flatpak_remove(ctx.runner, &entry.name, ctx.stream()),
        Backend::Brew => backend::brew_remove(ctx.runner, &entry.name, ctx.stream()),
        Backend::Distrobox => backend::distrobox_remove(
            ctx.runner,
            entry.from.as_deref().unwrap_or_default(),
            &entry.name,
            ctx.stream(),
        ),
    }
    .map_err(backend_err)?;
    m.remove(&entry);
    ctx.save(&m)?;
    Ok(Report {
        data: json!({
            "action": "remove",
            "package": entry.name,
            "backend": entry.backend,
            "from": entry.from,
            "dry_run": ctx.dry(),
            "commands": planned(ctx),
        }),
        text: done_text(ctx, &format!("removed {} ({})", entry.name, entry.backend)),
        ok: true,
    })
}

fn list(ctx: &Ctx) -> Result<Report, CliError> {
    let m = ctx.load()?;
    let mut text = String::new();
    for e in &m.packages {
        match &e.from {
            Some(f) => text.push_str(&format!("{:<10} {} (from {f})\n", e.backend, e.name)),
            None => text.push_str(&format!("{:<10} {}\n", e.backend, e.name)),
        }
    }
    if m.dx {
        text.push_str("dx         on\n");
    }
    if text.is_empty() {
        text.push_str("nothing recorded yet\n");
    }
    Ok(Report {
        data: json!({ "dx": m.dx, "packages": m.packages }),
        text: text.trim_end().to_string(),
        ok: true,
    })
}

fn search(ctx: &Ctx, a: &SearchArgs) -> Result<Report, CliError> {
    let mut errors: Vec<String> = Vec::new();
    let flatpak = match backend::flatpak_search(ctx.runner, &a.query) {
        Ok(v) => Some(v),
        Err(e) => {
            errors.push(e);
            None
        }
    };
    let brew = match backend::brew_search(ctx.runner, &a.query) {
        Ok(v) => Some(v),
        Err(e) => {
            errors.push(e);
            None
        }
    };
    if flatpak.is_none() && brew.is_none() {
        return Err(backend_err(errors.join("; ")));
    }
    let mut flatpak = flatpak.unwrap_or_default();
    let mut brew = brew.unwrap_or_default();
    flatpak.dedup_by(|x, y| x.0 == y.0);
    flatpak.truncate(a.limit);
    brew.truncate(a.limit);

    let mut text = String::new();
    for (id, name) in &flatpak {
        text.push_str(&format!("flatpak    {id}  {name}\n"));
    }
    for name in &brew {
        text.push_str(&format!("brew       {name}\n"));
    }
    for e in &errors {
        text.push_str(&format!("warning: {e}\n"));
    }
    if flatpak.is_empty() && brew.is_empty() {
        text.insert_str(0, "no matches\n");
    }
    let flatpak_json: Vec<Value> = flatpak
        .iter()
        .map(|(id, name)| json!({ "id": id, "name": name }))
        .collect();
    Ok(Report {
        data: json!({ "query": a.query, "flatpak": flatpak_json, "brew": brew, "errors": errors }),
        text: text.trim_end().to_string(),
        ok: true,
    })
}

fn sync(ctx: &Ctx) -> Result<Report, CliError> {
    let m = ctx.load()?;
    let mut installed: Vec<Value> = Vec::new();
    let mut present: Vec<Value> = Vec::new();
    let mut failed: Vec<Value> = Vec::new();

    for e in &m.packages {
        let item = json!({ "package": e.name, "backend": e.backend, "from": e.from });
        let result = sync_entry(ctx, e);
        match result {
            Ok(true) => present.push(item),
            Ok(false) => installed.push(item),
            Err(msg) => {
                let mut item = item;
                item["error"] = json!(msg);
                failed.push(item);
            }
        }
    }
    let mut dx_error: Option<String> = None;
    if m.dx {
        if let Err(e) = backend::dx_toggle(ctx.runner, true, ctx.stream()) {
            dx_error = Some(e);
        }
    }

    let mut text = format!(
        "{} installed, {} already present, {} failed",
        installed.len(),
        present.len(),
        failed.len()
    );
    if ctx.dry() {
        text = format!("dry run, nothing changed. {text}");
    }
    for f in &failed {
        text.push_str(&format!(
            "\n  failed: {} ({}): {}",
            f["package"], f["backend"], f["error"]
        ));
    }
    if let Some(e) = &dx_error {
        text.push_str(&format!("\n  failed: dx: {e}"));
    }
    let data = json!({
        "installed": installed,
        "already_present": present,
        "failed": failed,
        "dx": { "wanted": m.dx, "error": dx_error },
        "dry_run": ctx.dry(),
        "commands": planned(ctx),
    });
    let ok = failed.is_empty() && dx_error.is_none();
    Ok(Report { data, text, ok })
}

/// Ok(true) if already present, Ok(false) if it was installed now.
fn sync_entry(ctx: &Ctx, e: &Entry) -> Result<bool, String> {
    let from = e.from.as_deref().unwrap_or_default();
    let present = match e.backend {
        Backend::Flatpak => backend::flatpak_installed(ctx.runner, &e.name)?,
        Backend::Brew => backend::brew_installed(ctx.runner, &e.name)?,
        Backend::Distrobox => backend::distrobox_installed(ctx.runner, from, &e.name)?,
    };
    if present {
        return Ok(true);
    }
    match e.backend {
        Backend::Flatpak => backend::flatpak_install(ctx.runner, &e.name, ctx.stream())?,
        Backend::Brew => backend::brew_install(ctx.runner, &e.name, ctx.stream())?,
        Backend::Distrobox => backend::distrobox_install(ctx.runner, from, &e.name, ctx.stream())?,
    };
    Ok(false)
}
