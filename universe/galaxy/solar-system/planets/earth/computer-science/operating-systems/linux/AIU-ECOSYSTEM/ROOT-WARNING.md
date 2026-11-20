!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!                                                              !!!
!!!   WARNING: THIS SYSTEM HAS NO REAL ROOT                      !!!
!!!   READ THIS BEFORE FILE LOCKS, PERMISSIONS, BROOT, SERVER    !!!
!!!                                                              !!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

DO NOT DELETE THIS FILE. Add to it, never remove from it.

!!! THE SETUP
Shape works on a phone: Termux with PRoot. The shell runs as user
shape, uid 10349. It is NOT real root.
Tested 2026-11-20: in a dir with mode 555 a file with mode 444
denied append, mv and rm. So read-only bits work here today.

!!! WHY IT MATTERS
Lock 5 of broot step 8 (todo.aiu) makes managed files and dirs
read-only. Then no program can change them except the server, which
flips the bit only inside one operation. This is the only lock that
also stops outside tools: editors, scripts, git by hand.

!!! THE DANGER
If this ever runs as REAL ROOT (uid 0: a rooted phone, a root shell,
proot with a fake root id, a container as root, a Linux box as
root), read-only bits stop NOTHING. Root ignores them. The lock then
fails SILENTLY: the files look protected and they are not.
The same happens if the filesystem ignores chmod (some mounts,
shared storage, FAT).

!!! THE RULE
Never trust the lock without testing it.
The server must test at start: uid is not 0, and a test file with
mode 444 in a dir with mode 555 denies append, mv and rm.
If the test fails it must say NOT LOCKED loudly. Locks 1 to 4
(builtins, external program gate, redirection, build guard) do not
depend on permissions and stay in force.
Never remove this start check.

!!! WHEN REAL ROOT BECOMES AVAILABLE
Read this file again. Run the read-only test. Expect it to FAIL as
root and decide with Shape what replaces lock 5.

!!! PROBLEMS FOUND WITHOUT REAL ROOT (add here, never delete)
Shape expects specific problems with the file manager from having no
real root. None are recorded yet. Write each one here the moment it
is found, with the date and the command that showed it.
