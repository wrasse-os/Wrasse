//! The one place that spawns processes. Backends call `query` (read-only) and `act` (changes
//! the system). Tests build a `Runner::fake` with canned outputs; `--dry-run` uses
//! `Runner::dry_run`, which really runs queries but only records actions.

use std::cell::RefCell;
use std::process::{Command, Stdio};

const BREW_PATH: &str = "/home/linuxbrew/.linuxbrew/bin/brew";

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Output {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Output {
    pub fn ok(stdout: &str) -> Output {
        Output {
            code: 0,
            stdout: stdout.to_string(),
            stderr: String::new(),
        }
    }

    pub fn fail(code: i32) -> Output {
        Output {
            code,
            stdout: String::new(),
            stderr: String::new(),
        }
    }

    pub fn success(&self) -> bool {
        self.code == 0
    }
}

enum Mode {
    Real,
    DryRun,
    /// (command line prefix, canned output). The longest matching prefix wins.
    Fake(Vec<(String, Output)>),
}

pub struct Runner {
    mode: Mode,
    /// Every `act` call, as one command line each. In real mode this is what ran.
    acted: RefCell<Vec<String>>,
}

impl Runner {
    pub fn real() -> Runner {
        Runner::with(Mode::Real)
    }

    pub fn dry_run() -> Runner {
        Runner::with(Mode::DryRun)
    }

    /// Rules are `(command line prefix, output)`. An unmatched command is an error, so a test
    /// notices when code runs something it did not expect.
    pub fn fake(rules: Vec<(&str, Output)>) -> Runner {
        Runner::with(Mode::Fake(
            rules.into_iter().map(|(p, o)| (p.to_string(), o)).collect(),
        ))
    }

    fn with(mode: Mode) -> Runner {
        Runner {
            mode,
            acted: RefCell::new(Vec::new()),
        }
    }

    pub fn is_dry_run(&self) -> bool {
        matches!(self.mode, Mode::DryRun)
    }

    /// Commands passed to `act` so far, in order.
    pub fn acted(&self) -> Vec<String> {
        self.acted.borrow().clone()
    }

    /// Read-only command. Runs for real in real and dry-run mode. Output is captured.
    pub fn query(&self, prog: &str, args: &[&str]) -> Result<Output, String> {
        match &self.mode {
            Mode::Fake(rules) => fake_lookup(rules, prog, args),
            _ => spawn(prog, args, false),
        }
    }

    /// Command that changes the system. In dry-run mode it is only recorded. With `stream`
    /// the child inherits the terminal (progress, prompts); otherwise output is captured.
    pub fn act(&self, prog: &str, args: &[&str], stream: bool) -> Result<Output, String> {
        self.acted.borrow_mut().push(cmdline(prog, args));
        match &self.mode {
            Mode::DryRun => Ok(Output::ok("")),
            Mode::Fake(rules) => fake_lookup(rules, prog, args),
            Mode::Real => spawn(prog, args, stream),
        }
    }
}

pub fn cmdline(prog: &str, args: &[&str]) -> String {
    let mut s = prog.to_string();
    for a in args {
        s.push(' ');
        s.push_str(a);
    }
    s
}

fn fake_lookup(rules: &[(String, Output)], prog: &str, args: &[&str]) -> Result<Output, String> {
    let line = cmdline(prog, args);
    rules
        .iter()
        .filter(|(prefix, _)| line.starts_with(prefix.as_str()))
        .max_by_key(|(prefix, _)| prefix.len())
        .map(|(_, out)| out.clone())
        .ok_or_else(|| format!("fake runner: no rule for `{line}`"))
}

fn spawn(prog: &str, args: &[&str], stream: bool) -> Result<Output, String> {
    let exe = if prog == "brew" && std::path::Path::new(BREW_PATH).exists() {
        BREW_PATH
    } else {
        prog
    };
    let mut cmd = Command::new(exe);
    cmd.args(args);
    if stream {
        cmd.stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
        let status = cmd.status().map_err(|e| spawn_error(prog, &e))?;
        return Ok(Output {
            code: status.code().unwrap_or(-1),
            stdout: String::new(),
            stderr: String::new(),
        });
    }
    let out = cmd
        .stdin(Stdio::null())
        .output()
        .map_err(|e| spawn_error(prog, &e))?;
    Ok(Output {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    })
}

fn spawn_error(prog: &str, e: &std::io::Error) -> String {
    if e.kind() == std::io::ErrorKind::NotFound {
        format!("`{prog}` was not found on PATH")
    } else {
        format!("could not run `{prog}`: {e}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fake_picks_longest_prefix() {
        let r = Runner::fake(vec![
            ("flatpak", Output::fail(9)),
            ("flatpak info", Output::ok("hi")),
        ]);
        assert_eq!(r.query("flatpak", &["info", "x"]).unwrap().stdout, "hi");
        assert_eq!(r.query("flatpak", &["list"]).unwrap().code, 9);
    }

    #[test]
    fn fake_unmatched_is_error() {
        let r = Runner::fake(vec![]);
        assert!(r.query("brew", &["list"]).is_err());
    }

    #[test]
    fn dry_run_records_but_does_not_run() {
        let r = Runner::dry_run();
        let out = r
            .act("definitely-not-a-real-binary", &["x"], false)
            .unwrap();
        assert!(out.success());
        assert_eq!(r.acted(), vec!["definitely-not-a-real-binary x"]);
    }

    #[test]
    fn missing_binary_is_reported() {
        let r = Runner::real();
        let err = r.query("definitely-not-a-real-binary", &[]).unwrap_err();
        assert!(err.contains("not found"));
    }
}
