# Borgbar

Watch [Borg](https://borgbackup.org) / [borgmatic](https://torsion.org/borgmatic/)
backups from the [Omarchy](https://omarchy.org) bar: when the last one ran,
whether it worked, and when the next one is due.

## Why

A backup you never look at is a backup you are trusting on faith. This puts the
answer on the bar: a hard-disk icon that stays quiet when the last run
succeeded recently, and goes urgent when it failed or went stale.

## How it reads state

Two very different costs, split deliberately:

- **systemd** knows when the timer last fired, when it fires next, and how the
  last run ended. That is local and instant, so it is polled.
- **The repository** has to be asked over the network what archives it holds,
  which takes seconds. That is never polled — it is cached and only refreshed
  when you press *Check repo*.

## Requirements

```bash
omarchy pkg add borg borgmatic jq
```

A `borgmatic.timer` under either systemd `--user` or the system manager;
Borgbar finds whichever owns it.

## Install

```bash
omarchy plugin add https://github.com/epicbagel/borgbar.git --enable
omarchy-restart-shell
```

The restart matters: `omarchy plugin update` reloads a plugin's service but
does not re-instantiate its bar widget.

## Use

Left click opens the panel; middle click starts a backup immediately.

```bash
borgbar status     # one JSON object
borgbar run        # start borgmatic.service now
borgbar refresh    # ask the repository for its latest archive (slow)
borgbar logs [n]   # recent journal lines for the service
borgbar doctor
```

## Removing it

```bash
omarchy plugin remove io.github.epicbagel.borgbar
omarchy-restart-shell
rm -rf ~/.cache/borgbar ~/.config/borgbar
```

## Notes

The bar shows `ok` when the last run succeeded within `staleHours` (default 24),
`stale` past that, `failed` on a non-zero exit or a non-success systemd result,
and `running` while a backup is in flight.

Running is detected from the systemd unit, and from a process named exactly
`borgmatic`. Matching the whole command line instead would report a backup in
progress whenever anything merely mentions borgmatic — a shell, an editor, a
grep — which is a surprisingly easy way to make a status widget lie.

## License

MIT
