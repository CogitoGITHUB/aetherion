
#[path = "../bake/bake_file.rs"]
mod bake;
#[path = "../config.rs"]
mod config;
#[path = "../last_good/last_good_record.rs"]
mod last_good;

use std::path::PathBuf;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(code) => std::process::exit(code),
        Err(why) => {
            eprintln!("mux-bake: {}", why);
            std::process::exit(2);
        }
    }
}

fn run(args: &[String]) -> Result<i32, String> {
    let options = Options::read(args)?;
    println!("mux-bake: the state directory: {}", options.state_dir.display());

    let baked = match &options.config {
        Some(source) => {
            println!("mux-bake: the config to bake: {}", source.display());
            bake::bake_file(&options.state_dir, source)
        }
        None => {
            let in_force = config::ConfigFile::start(&options.state_dir);
            println!("mux-bake: the config in force: {}", in_force.origin());
            bake::bake(&options.state_dir, in_force.config())
        }
    };

    for line in baked.report() {
        println!("mux-bake: {}", line);
    }
    Ok(if baked.good { 0 } else { 1 })
}

struct Options {
    state_dir: PathBuf,
    config: Option<PathBuf>,
}

impl Options {
    fn read(args: &[String]) -> Result<Options, String> {
        let mut state_dir: Option<PathBuf> = None;
        let mut config: Option<PathBuf> = None;
        let mut at = 0;
        while at < args.len() {
            let name = args[at].clone();
            let value = match args.get(at + 1) {
                Some(found) => found.clone(),
                None => return Err(format!("{} needs a value", name)),
            };
            match name.as_str() {
                "--state-dir" => {
                    state_dir = Some(PathBuf::from(value));
                    at += 2;
                }
                "--config" => {
                    config = Some(PathBuf::from(value));
                    at += 2;
                }
                "--help" => {
                    println!("mux-bake --state-dir DIR [--config PATH]");
                    println!("  the config in force is baked when --config names no file");
                    std::process::exit(0);
                }
                other => return Err(format!("{} is not an option this command knows", other)),
            }
        }
        let state_dir = state_dir.ok_or("the bake needs --state-dir")?;
        Ok(Options { state_dir, config })
    }
}
