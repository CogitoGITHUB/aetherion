module completions {

  # A smarter cd command for your terminal
  export extern aiu-shell-jump [
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Add a new directory or increment its rank
  export extern "aiu-shell-jump add" [
    --score(-s): string       # The rank to increment the entry if it exists or initialize it with if it doesn't
    --help(-h)                # Print help
    --version(-V)             # Print version
    ...paths: path
  ]

  # Edit the database
  export extern "aiu-shell-jump edit" [
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  export extern "aiu-shell-jump edit decrement" [
    --help(-h)                # Print help
    --version(-V)             # Print version
    path: string
  ]

  export extern "aiu-shell-jump edit delete" [
    --help(-h)                # Print help
    --version(-V)             # Print version
    path: string
  ]

  export extern "aiu-shell-jump edit increment" [
    --help(-h)                # Print help
    --version(-V)             # Print version
    path: string
  ]

  export extern "aiu-shell-jump edit reload" [
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Import entries from another application
  export extern "aiu-shell-jump import" [
    --merge                   # Merge into existing database
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Import from atuin
  export extern "aiu-shell-jump import atuin" [
    --merge                   # Merge into existing database
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Import from autojump
  export extern "aiu-shell-jump import autojump" [
    --merge                   # Merge into existing database
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Import from fasd
  export extern "aiu-shell-jump import fasd" [
    --merge                   # Merge into existing database
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Import from z
  export extern "aiu-shell-jump import z" [
    --merge                   # Merge into existing database
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Import from z.lua
  export extern "aiu-shell-jump import z.lua" [
    --merge                   # Merge into existing database
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Import from zsh-z
  export extern "aiu-shell-jump import zsh-z" [
    --merge                   # Merge into existing database
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  def "nu-complete aiu-shell-jump init shell" [] {
    [ "bash" "elvish" "fish" "nushell" "posix" "powershell" "tcsh" "xonsh" "zsh" ]
  }

  def "nu-complete aiu-shell-jump init hook" [] {
    [ "none" "prompt" "pwd" ]
  }

  # Generate shell configuration
  export extern "aiu-shell-jump init" [
    --no-cmd                  # Prevents aiu-shell-jump from defining the `z` and `zi` commands
    --cmd: string             # Changes the prefix of the `z` and `zi` commands
    --hook: string@"nu-complete aiu-shell-jump init hook" # Changes how often aiu-shell-jump increments a directory's score
    --help(-h)                # Print help
    --version(-V)             # Print version
    shell: string@"nu-complete aiu-shell-jump init shell"
  ]

  # Search for a directory in the database
  export extern "aiu-shell-jump query" [
    --all(-a)                 # Show unavailable directories
    --interactive(-i)         # Use interactive selection
    --list(-l)                # List all matching directories
    --score(-s)               # Print score with results
    --exclude: path           # Exclude the current directory
    --base-dir: path          # Only search within this directory
    --help(-h)                # Print help
    --version(-V)             # Print version
    ...keywords: string
  ]

  # Remove a directory from the database
  export extern "aiu-shell-jump remove" [
    --help(-h)                # Print help
    --version(-V)             # Print version
    ...paths: path
  ]

}

export use completions *
