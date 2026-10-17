# Third-Party Notices

## Syncthing

The Beta and Stable Android builds of this project embed the Syncthing core
executable as the peer-to-peer transport used by the in-app device sync
feature.

- Component: Syncthing
- Pinned source version: v2.1.5
- Upstream source: https://github.com/syncthing/syncthing/tree/v2.1.5
- License: Mozilla Public License 2.0
- License copy: `third_party/syncthing/LICENSE`

The embedded executable is built from the unmodified upstream source at the
pinned tag by `tool/build_syncthing_android.sh`. The application-specific
Dart/Kotlin synchronization layer remains separate from the Syncthing source.


## VPet-Simulator.Core

The Windows desktop-pet companion uses VPet-Simulator.Core as its WPF
desktop-pet rendering foundation.

- Component: VPet-Simulator.Core
- Package version: 1.1.0.66
- Upstream source: https://github.com/LorisYounger/VPet
- License: Apache License 2.0
- License copy: `windows/desktop_pet/LICENSE-VPET.txt`
- Component notice: `windows/desktop_pet/THIRD_PARTY_NOTICES.txt`

Adventurer's Guild supplies its own user-imported A/B images at runtime and
does not redistribute VPet's built-in character animation assets.
