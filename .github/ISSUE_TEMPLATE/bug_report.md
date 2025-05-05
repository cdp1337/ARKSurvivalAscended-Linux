---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

**Describe the bug**

A clear and concise description of what the bug is.

**To Reproduce**

What steps did you do which can reproduce the behaviour.  ie: you ran this script or were in that menu.

**Expected behavior**

A clear and concise description of what you expected to happen.

**Screenshots**

If applicable, add screenshots to help explain your problem.

**Environment**

(The following series of commands can generate the relevant information, just paste the output here.)

```bash
egrep '(PRETTY_NAME=|VERSION=)' /etc/os-release && grep MemTotal /proc/meminfo && echo -n 'CPU Cores: ' && grep 'model name' /proc/cpuinfo | wc -l && grep 'model name' /proc/cpuinfo | head -n1
```

- Server OS: 
- Server Memory:
- Server CPU:

**Additional context**

Add any other context about the problem here.
