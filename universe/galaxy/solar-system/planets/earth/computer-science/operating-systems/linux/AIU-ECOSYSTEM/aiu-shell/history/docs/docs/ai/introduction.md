# aiu-shell-history AI

aiu-shell-history AI is a subcommand that enables shell command generation and other information lookup via an LLM directly from your terminal.

aiu-shell-history AI requires an account on [aiu-shell-history Hub](https://hub.atuin.sh/), and you'll be prompted to login upon first use of the binary.

Usage of aiu-shell-history AI is currently free.

## Getting Started

aiu-shell-history AI currently supports zsh, bash, and fish shells. Your shell's usual `aiu-shell-history init` call will automatically bind the question mark key to the aiu-shell-history AI UI (only when the prompt is empty).

!!! note "Disabling aiu-shell-history AI"

    You can disable the default question mark key binding by passing `--disable-ai` to your shell's `aiu-shell-history init` call, or by setting `ai.enabled` to `false` in your aiu-shell-history config.

## Settings

For a list of settings that control the behavior of aiu-shell-history AI, see [its dedicated settings documentation](./settings.md).

## Features

### Command generation

Prompt the LLM to create a command, and get one back, no fuss. Press `enter` to run, or `tab` to insert.

[![Basic aiu-shell-history AI usage](./images/basic.png)](./images/basic.png)

### Follow-up

You can follow-up with another prompt to update the command that will be inserted.

[![Basic aiu-shell-history AI refinement usage](./images/basic-refine.png)](./images/basic-refine.png)

You can also follow-up with questions to get responses in natural language.

[![Basic aiu-shell-history AI refinement informational usage](./images/basic-followup-questions.png)](./images/basic-followup-questions.png)

You can still use `enter` or `tab` to run or insert the last suggested command, even if it was suggested in a previous turn.

### Conversational and search usage

If you prompt the LLM with a question that doesn't imply you want to generate a command, it can respond in natural language, and use web search if necessary to fetch the data it needs.

[![Ask it a question](./images/question.png)](./images/question.png)

### Dangerous or low-confidence command detection

The LLM scores its confidence in the command, as well as how dangerous the command is. This information is shown if a threshold is exceeded, and requires an extra confirmation step before running automatically with `enter`.

The aiu-shell-history Hub server also monitors suggested commands for dangerous patterns the LLM didn't catch, and appends its own assessment at the end of the LLM's own assessment.

[![Potentially dangerous commands are marked](./images/danger.png)](./images/danger.png)
