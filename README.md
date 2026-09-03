```bash
g co flash-3.8 && g c "gemini 3.8 flash high" && g co staging && g reset --hard flash-3.8 && g h --force origin staging && g co flash-3.8 && g uc
```

with `alias g=git` and the following `gitconfig`

```
[user]
	name = Kent Slaney
	email = kent@slaney.org
[filter "lfs"]
	clean = git-lfs clean -- %f
	smudge = git-lfs smudge -- %f
	process = git-lfs filter-process
	required = true
[alias]
	cob = checkout -b
	c = !git add -A && git commit -m
	s = status
	co = checkout
	p = pull --no-edit
	d = diff -b
	h = push
	l = log --decorate
	cl = clone
	sh = stash
	b = branch
	a = add
	cm = commit -m
	cp = cherry-pick
	lol = log --graph --oneline --decorate --color --all
	y = blame
    uc = !git reset --soft HEAD~1 && git restore --staged .
    o = show
[core]
	autocrlf = input
	editor = vim
[protocol "file"]
	allow = always
[push]
	autoSetupRemote = true
	default = current
[init]
	defaultBranch = main
```
