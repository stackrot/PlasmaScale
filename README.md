# PlasmaScale

PlasmaScale is a KDE Plasma 6 widget for monitoring and controlling the local Tailscale client.

It shows connection state, peer availability, addresses, traffic totals and recent activity. The popup can connect or disconnect Tailscale, copy peer addresses and select grouped geographic or personal exit nodes.

## Requirements

- KDE Plasma 6
- `plasma5support`, used to run the `tailscale` commands (minimal Plasma installs may not include it)
- The `tailscale` CLI installed and authenticated
- `kpackagetool6` for installation

Status monitoring works with ordinary user permissions. Control actions require your Linux user to be the Tailscale operator:

```bash
sudo tailscale set --operator="$USER"
```

## Install

1. Download `PlasmaScale-1.0.0.plasmoid` from the [latest release](https://github.com/stackrot/PlasmaScale/releases/latest).
2. Move the downloaded file to `~/Downloads`.
3. Run:

   ```bash
   kpackagetool6 --type Plasma/Applet --install ~/Downloads/PlasmaScale-1.0.0.plasmoid
   ```

4. Right-click the Plasma panel, select **Add or Manage Widgets**, search for **PlasmaScale**, then add it to the panel or System Tray.

## Update

Download the new release and run:

```bash
kpackagetool6 --type Plasma/Applet --upgrade ~/Downloads/PlasmaScale-VERSION.plasmoid
```

## Remove

```bash
kpackagetool6 --type Plasma/Applet --remove com.stackrot.plasmascale
```

## Build from source

```bash
git clone https://github.com/stackrot/PlasmaScale.git
cd PlasmaScale
make check
make package
```

The installable archive is written to `dist/`.

Use `make install` for a first installation or `make upgrade` when PlasmaScale is already installed.

## Commands used

PlasmaScale invokes only the local Tailscale CLI:

```text
tailscale status --json
tailscale up
tailscale down
tailscale set --exit-node=ADDRESS
tailscale set --exit-node=
```

No Tailscale credentials or status data leave the machine.

## Licence

PlasmaScale is released under the MIT License.

Tailscale is a trademark of Tailscale Inc. PlasmaScale is an independent community project and is not affiliated with or endorsed by Tailscale Inc.

The Tailscale mark is sourced from [Simple Icons](https://simpleicons.org/?q=tailscale) under CC0 1.0; trademark rights remain with Tailscale Inc.
