R=$(cat $HOME/.local/state/aiu-ecosystem/root)
cd "$R"
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PLTCOMPILEDROOTS=$HOME/aiu-compiled
exec $HOME/opt/racket-full/bin/racket "AIU ECOSYSTEM/ecosystem/ecosystem TUI configuration/settings-tui.rkt"
