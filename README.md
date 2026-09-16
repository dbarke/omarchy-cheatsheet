# omarchy-cheatsheet

A staged keybinding cheat sheet for [Omarchy](https://omarchy.org/): essentials
first, power moves later, with the keys you've learned ticked off.

`Super+K` lists every binding, which is great for looking things up and too much
for learning. This overlay teaches in tiers — Essentials, Faster, Power, and a
herdr tier for the terminal — and tracks your progress per tier.

Keys are read live from `omarchy-menu-keybindings --print`, so rebinds show up
automatically and entries whose binding doesn't exist are hidden.

![The Essentials tier: keys on the left, what they do on the right, learned ones
ticked and dimmed](preview.png)

## Install

```bash
omarchy plugin add https://github.com/dbarke/omarchy-cheatsheet.git --enable
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + F1", "Cheat sheet", "omarchy-shell shell toggle dbarke.cheatsheet")
```

## Use

| Key | Action |
|---|---|
| Click / `Space` | Mark learned |
| `1`–`3`, `Tab` | Switch tier |
| `H` | Hide / show learned |
| `Esc`, `Super+F1` | Close |

## Customize

Edit `tiers.json`. Each entry names a binding by its description as shown in
`omarchy menu keybindings --print`; `label` and `hint` are what the sheet shows,
and `key` overrides the key cap for grouped bindings (e.g. `"1 … 9"`).

Entries with `"herdr": "<action>"` instead of `desc` take their keys from the
`[keys]` table of `~/.config/herdr/config.toml` (the first binding listed, with
the prefix chord shown as one cap; add `"chord": true` to prefer a binding
without the prefix). Actions not set there are left out.
Learned state lives in `~/.local/state/omarchy/cheatsheet-learned.json`.
