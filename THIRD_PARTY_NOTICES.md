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
