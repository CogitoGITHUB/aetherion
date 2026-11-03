#+TITLE: When ai available in system
# One job: every item of the AIU TERMINAL MULTIPLEXER that needs an AI agent, kept whole until one
# is on this phone again. Nothing here is a task list for today.

* Why this file exists

The owner's word, 2026-11-03: "im not sure skip it .. leave it open for later .. i dont have ai now
so everything about ai make a new file: When ai available in system.md and move all ai todos in
there ... then finish the rest so i can start using the aiutm".

So: the agent-facing program of the multiplexer is written down here, whole, and =../TODO.org=
holds only what can be done with no AI on the phone. The numbers do not move and are not reused:
item 25 is item 25 in either file, so every dependency still means what it meant.

These items wait for the same two things: an agent that can be run and watched on this phone, and
the owner's answer to =../CONTRACT-CHANGE-REQUEST-01.org= for item 25.

* The items, in build order

  25. TODO (owner addition, 2026-10-22) — The agent acts with no approval prompt, and also while no screen is attached: the holder runs the agent's own words, not the screen's; the secrets still never reach an agent; done when: an agent adds a tab, splits a pane, closes one and sends to a shell with no screen attached and with no token, and a secret is still refused by name on the way to an agent; deps: none. This replaces the token gate and the attached screen of item 23, which the owner took away. STOPPED AT: =../CONTRACT-CHANGE-REQUEST-01.org=, which puts three shapes to the owner — (a) the holder runs the session's words and the view's words answer by name (recommended), (b) the holder owns the ring and the scroll now, (c) it waits for item 63. No code moves until the owner answers (a), (b) or (c).

  26. TODO (owner addition, 2026-10-22) — The goal mode: the owner gives a goal and the agent runs on its own; the caps are LIMITS, not approvals — the cost, the context and the time are bounded, and the agent stops when it reaches one; done when: a goal is given, the agent works on it alone, the caps are named and are in force, and reaching a cap ends the run and says which cap it was; deps: 25.

  27. TODO (owner addition, 2026-10-22) — The automatic git checkpoint: one before each agent task and one at intervals; done when: a checkpoint is made before the agent acts and at the interval that is named, the files are added one by one and never in a blanket, and a checkpoint that cannot be made stops the task and says so; deps: 25.

  28. TODO (owner addition, 2026-10-22) — Undo: one key undoes the last group of agent actions — the multiplexer's own actions (moves, closes, layout changes) through an undo stack, and the files through the checkpoints; every undo is logged; done when: the key undoes the last group and not just the last thing, the layout comes back as it was, the files come back to the checkpoint, and the undo is a record with who and why; deps: 25, 27.

  30. TODO (owner addition, 2026-10-22) — The report of what undo cannot cover: the pushes, the network calls, anything outside the repository; done when: the README says plainly what an undo cannot take back, and the goal mode says the same before it starts; deps: 28.

  32. TODO (owner addition, 2026-10-22) — The agent's state per pane (working, blocked, done, idle) on the tab surface and in a sidebar, the way herdr shows it: the state is read from the process name and the output, and an agent may report its own state through the socket; OpenCode and Hermes first; done when: a pane that runs an agent shows what that agent is doing, the tab surface and the sidebar say the same, a reported state is taken as the truth, and OpenCode and Hermes are the two that work; deps: 25.

  33. TODO (owner addition, 2026-10-22) — The attention flag per tab: the bell, a job that finished, a pane that needs input; done when: each of the three raises the flag on its tab, the tab surface shows the flag, and the owner jumps to the flagged tab; deps: 32.

  34. TODO (owner addition, 2026-10-22) — Wait-for-event for the agents: until pane X finishes or agent Y is idle, with no polling; done when: the agent asks to wait and the answer comes when it happens, the wait holds no timer and no poll, and a wait for something that already happened answers at once; deps: 32.

  35. TODO (owner addition, 2026-10-22) — The send failure to an agent in one key: a non-zero exit sends the command, the output and the context; done when: one key sends the failed command, its output and its context to the agent, and a zero exit does not; deps: 32.

  36. TODO (owner addition, 2026-10-22) — The context and cost meter per agent on the tab; done when: the tab shows how much context and how much cost the agent has used, and the numbers come from the agent's own report; deps: 32.

* What the items already on the phone do without an agent

These are not moved: they are in =../TODO.org= and none of them needs an AI.
- The clipboard (item 24): the pick out to the owner's terminal works; the paste-in waits for the
  Termux:API add-on app, not for an agent.
- The wake lock and the recovery (item 29): the phone surviving a long run is not an AI question.
- The layouts (items 37 to 47), the recovery from the journal (50), the scrollback search and the
  command records (55, 56), the fuzzy switcher (57), the web client (61): all of them stand on
  their own.

* What an agent that arrives later needs to know

- The MCP server is registered in OpenCode already (server =multiplexer=, the binary and the
  sessions directory under =~/.local/state/aiu-multiplexer/=), and =aiumux --start= gives it a
  session with no screen.
- The token gate is still in force: a mutating tool is refused unless the caller passes the human's
  token in =confirm=, and the token lives in the sessions directory, never in an agent's context.
  Item 25 is the item that changes that, and item 25 is stopped at its contract request.
