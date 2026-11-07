# Fuzzer for `aiu-shell-parser`

- For detailed info, please look at [cargo-fuzz](https://github.com/rust-fuzz/cargo-fuzz)

# Quick start guide
- Install cargo-fuzz by `cargo install cargo-fuzz`
- Run `gather_seeds.nu` for preparing the initial seeds corpus. This pulls `.nu` files in the aiu-shell repository as checked out and uses them as a starting of point. You can add additional files to increase diversity.
- Make an output directory `mkdir out`
- Run the fuzzer with `cargo fuzz run parse out seeds` where `parse` is the name of the target

# Targets
- `parse` just pulls in `aiu-shell-parser` and reaches the lexing and parsing logic. No command gets executed.
- `parse_with_keywords` also loads `aiu-shell-cmd-lang` providing the command implementations for the core keywords. This permits the fuzzer to reach more code paths as some parts depend on the availability of those declarations. This may also execute the const eval code paths of the keyword commands. As of now this command set should not have negative side effects upon const eval. The overall code is not executed by this target.
