use clap::Parser;
use std::io::{BufRead, IsTerminal, Write};
use wrasse::app::{run, Cli, CliError, Ctx};
use wrasse::manifest::config_dir;
use wrasse::runner::Runner;

fn main() {
    let cli = Cli::parse();
    let code = match go(&cli) {
        Ok(true) => 0,
        Ok(false) => 1,
        Err(e) => {
            if cli.json {
                println!("{}", e.to_json());
            } else {
                eprintln!("wrasse: {}", e.message);
            }
            e.exit_code()
        }
    };
    std::process::exit(code);
}

/// Ok(false) means the command ran but part of it failed; the report was already printed.
fn go(cli: &Cli) -> Result<bool, CliError> {
    let dir = config_dir().map_err(|m| CliError {
        code: "config",
        message: m,
    })?;
    let runner = if cli.dry_run {
        Runner::dry_run()
    } else {
        Runner::real()
    };
    let ctx = Ctx {
        dir: &dir,
        runner: &runner,
        json: cli.json,
    };
    let interactive = !cli.json && std::io::stdin().is_terminal();
    let mut ask = |question: &str| -> Option<String> {
        if !interactive {
            return None;
        }
        eprint!("{question}");
        let _ = std::io::stderr().flush();
        let mut line = String::new();
        std::io::stdin().lock().read_line(&mut line).ok()?;
        Some(line)
    };
    let report = run(cli, &ctx, &mut ask)?;
    if cli.json {
        println!("{}", report.to_json());
    } else {
        println!("{}", report.text);
    }
    Ok(report.ok)
}
