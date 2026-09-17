# dockpid

Appends the process ID of each running app to its Dock tile label, with
configurable styles and live updates.

<img width="131" alt="A Dock tile labelled with its process id" src="https://github.com/user-attachments/assets/8f270078-2dea-4eca-bf8f-5ad1f6422395" />

## Requirements

macOS on Apple silicon (arm64e), with
[TweakInject](https://github.com/doraorak/TweakInject) installed — it provides
the loader that injects this tweak, and
[PreferenceLoaderX](https://github.com/doraorak/PreferenceLoaderX), which draws
the settings page. Both are listed in `control` as dependencies, so installing
through TweakInject pulls them in.

TweakInject requires SIP to be disabled; see its README for what that means and
what it costs. No boot arguments are needed.

## Building

```bash
./package.sh
```

Produces a standard `.deb` in `packages/`. The script compiles the tweak for
arm64e, stages `layout/` over it and writes the archive itself, so the only
thing it needs from Theos is `logos.pl` for the `.x` preprocessor.

A `Makefile` is included for `make clean package` under Theos, but `package.sh`
is the path that is kept current — it resolves `TI_PreferenceSupport` from a
local TweakInject checkout when the library is not installed system-wide, which
a plain Theos build does not do.

## Installing

Open the `.deb` with TweakInject, or install it from the TI Store, where this
tweak is published. TweakInject handles the dependencies, the injection and the
restart; nothing has to be copied by hand.

## Preferences

Settings live in **TweakInject → Installed Tweaks → dockpid**, drawn from
[`Root.plist`](layout/Library/TweakInject/Preferences/PreferenceBundles/dockpidPrefs.bundle/Root.plist)
by PreferenceLoaderX. Changes post
`com.doraorak.dockpid/prefsChanged` and apply live, with no restart.

## License

See [LICENSE](LICENSE).
