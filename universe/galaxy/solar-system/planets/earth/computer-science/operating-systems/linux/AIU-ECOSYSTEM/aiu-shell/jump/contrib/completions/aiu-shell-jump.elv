
use builtin;
use str;

set edit:completion:arg-completer[aiu-shell-jump] = {|@words|
    fn spaces {|n|
        builtin:repeat $n ' ' | str:join ''
    }
    fn cand {|text desc|
        edit:complex-candidate $text &display=$text' '(spaces (- 14 (wcswidth $text)))$desc
    }
    var command = 'aiu-shell-jump'
    for word $words[1..-1] {
        if (str:has-prefix $word '-') {
            break
        }
        set command = $command';'$word
    }
    var completions = [
        &'aiu-shell-jump'= {
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
            cand add 'Add a new directory or increment its rank'
            cand edit 'Edit the database'
            cand import 'Import entries from another application'
            cand init 'Generate shell configuration'
            cand query 'Search for a directory in the database'
            cand remove 'Remove a directory from the database'
        }
        &'aiu-shell-jump;add'= {
            cand -s 'The rank to increment the entry if it exists or initialize it with if it doesn''t'
            cand --score 'The rank to increment the entry if it exists or initialize it with if it doesn''t'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;edit'= {
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
            cand decrement 'decrement'
            cand delete 'delete'
            cand increment 'increment'
            cand reload 'reload'
        }
        &'aiu-shell-jump;edit;decrement'= {
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;edit;delete'= {
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;edit;increment'= {
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;edit;reload'= {
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;import'= {
            cand --merge 'Merge into existing database'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
            cand atuin 'Import from atuin'
            cand autojump 'Import from autojump'
            cand fasd 'Import from fasd'
            cand z 'Import from z'
            cand z.lua 'Import from z.lua'
            cand zsh-z 'Import from zsh-z'
        }
        &'aiu-shell-jump;import;atuin'= {
            cand --merge 'Merge into existing database'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;import;autojump'= {
            cand --merge 'Merge into existing database'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;import;fasd'= {
            cand --merge 'Merge into existing database'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;import;z'= {
            cand --merge 'Merge into existing database'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;import;z.lua'= {
            cand --merge 'Merge into existing database'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;import;zsh-z'= {
            cand --merge 'Merge into existing database'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;init'= {
            cand --cmd 'Changes the prefix of the `z` and `zi` commands'
            cand --hook 'Changes how often aiu-shell-jump increments a directory''s score'
            cand --no-cmd 'Prevents aiu-shell-jump from defining the `z` and `zi` commands'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;query'= {
            cand --exclude 'Exclude the current directory'
            cand --base-dir 'Only search within this directory'
            cand -a 'Show unavailable directories'
            cand --all 'Show unavailable directories'
            cand -i 'Use interactive selection'
            cand --interactive 'Use interactive selection'
            cand -l 'List all matching directories'
            cand --list 'List all matching directories'
            cand -s 'Print score with results'
            cand --score 'Print score with results'
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
        &'aiu-shell-jump;remove'= {
            cand -h 'Print help'
            cand --help 'Print help'
            cand -V 'Print version'
            cand --version 'Print version'
        }
    ]
    $completions[$command]
}
