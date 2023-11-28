# progpipe

A universal bash progress printer with ETC and many other functions. 

[progpipe](https://github.com/altometer/progpipe) works with __ANY__ incoming number that increases or decreases in size towards a goal. Unlike [pv](https://man7.org/linux/man-pages/man1/pv.1.html) you aren't limited to *monitor the progress of **data** through a pipe*". 

It's *this* simple. `(some arbitrary stdout) | progpipe 10`
```
[ 33.3333% 4/10 ]       avg/s:.2000     etc:2023-11-01 12:05:54
```

I wrote this after becoming frustrated with the lack of a clear and simple progress estimation function available to bash.

# Dependencies
- progpipe was written for [bash](https://www.gnu.org/software/bash/), but will work with most other shells.
- [bc](https://ss64.com/bash/bc.html) for float math

# Autocomplete
- Thanks to ChatGPT, whipped this up in a few seconds.
> write a bash-completions script for this code `...`

`sudo cp progpipe_autocomplete /usr/share/bash-completion/completions/progpipe`

# Usage Scenario 1: A rapidly filling system disk
A disk is rapidly filling up on one of your servers. How long do you have left before the system freezes?

Get the current disk usage:
```bash
$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2        98G  8.6G   84G  10% /
```

Cleaning up the line and looping the output
```bash
$ while :; do df / | tr -d "%" | tail -n1;sleep 1;done
...
/dev/sda2      102169560 11959096  84977520  13 /
/dev/sda2      102169560 12410948  84525668  13 /
/dev/sda2      102169560 12762764  84173852  14 /
/dev/sda2      102169560 12959100  83977516  14 /
...
```

Even from this report we can see the disk % is going up FAST.

Quick, throw that in to progpipe to get a REAL eta.

> Shortcut command `$ !! | progpope -g 99 -f 5`

```bash
$ while :; do 
    df / | tr -d "%" | tail -n1
    sleep 1
  done | progpipe --goal-num 99 --field-sel 5
```
```
[ 8.8607% 27/99 ]	avg/s:.1458	etc:2022-06-02 20:12:55
```
Uh oh, that's saying since we've started watching:
- `8.8607%` increase in the monitored value
- `27/99` of our goal (In this case, % of disk used)
- `avg/s:.1458` A huge .1458 % of disk PER SECOND
- `etc:2022-06-02 20:12:55` I have only a few hours

Using the verbose option
```bash
$ while :; do 
    df / | tr -d "%" | tail -n1
    sleep 1
  done | progpipe -g 99 -ff 5 --verbose
```

```bash
[ 2.7777% 29/99 ]	avg/s:.0666	etc:2022-06-02 20:30:09
---
Days:		.0121
Hours:		.2919
Minutes:	17.5166
Seconds:	1051
```

Alternatively, we can track the bytes remaining field and estimate how long it will take to get to ANY value 0 or above.

```bash
$ while :; do
    df / | tail -n1
    sleep 1
  done | progpipe -g 10000 -f 4 -v
```
```bash
[ 2.9944% 83118508/10000 ]	avg/s:135024.2105	etc:2022-06-02 20:28:34
---
Days:		.0071
Hours:		.1708
Minutes:	10.2500
Seconds:	615
```
Notice that the `avg/s` now reads `135024.2105` indicating the average change in bytes per second.

# Usage Scenario 2: How long until my cleanup script finishes?

If your script iterates over millions of loops like mine often do, this is a lifesaver.

```bash
$ for file in $(find /my/file/path/);do
    rm $file
  done
```
Assuming that each file is several GB in size, this can take QUITE a long time to finish. The easiest way to monitor it would be with the following progpipe command.
```bash
$ while :; do
    find /my/file/path/ | wc -l
    sleep 1
  done | progpipe -g 0
```

## A more complicated cleanup script example

Given the script below that will only remove SOME of the files in a directory:
```bash
# Remove files with zeros in their names
$ for file in $(find /my/file/path/);do
    if [[ "$file" =~ .*0.* ]];then
    echo "Removing $file"
    rm $file
    fi
  done
```
This actually isn't more complicated for progpipe. It's still only counting the decrementing files. Instead of setting the goal to `0`, we set it to the correct/estimated number.

```bash
# Get the number of files
$ find . | wc -l
88890

# Get the number of files with zeros in the name
$ find . -name "*0*" | wc -l
29841

# What's the new goal number of files?
$ echo $((88890 - 29841))
59049
```
This makes our progpipe command:
```bash
$ while :; do
    find /my/file/path/ | wc -l
    sleep 1
  done | progpipe -g 59049
```

```
[ .3219% 88771/59049 ]  avg/s:9.6000    etc:2022-06-02 21:38:52
```

# Usage Scenario 3: Waiting on a super slow SD card or USB drive
You've just finished copy/pasting your files and know to use the `sync` command to safely eject, but the command hangs!

```bash
# Show how much dirty memory the system has
$ grep Dirty: /proc/meminfo
Dirty:               7320 kB

# You know the drill, keep outputting the values as time-series data, then pipe it to progpipe

# on one line
$ while :;do grep Dirty: /proc/meminfo;sleep 1;done | progpipe -f 2 -g 0

# Nice formatting
$ while :;do
    grep Dirty: /proc/meminfo
    sleep 1
  done | progpipe -f 2 -g 0
```

`Dirty:               (7320) kB`

Option `-f 2` selects the correct field and `-g 0` tells progpipe this is a decrementing value to track down to zero.
