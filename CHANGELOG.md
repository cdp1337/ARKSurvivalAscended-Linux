## 2026-07-04

### Changed

* Updated first-run to ensure default maps exist, useful for new maps

### Added

* Add Genesis 1 map to default list

## 2026-05-23

### Changed

* Move default cluster ID and default admin password logic to Python
* Implement new passphrase generation to generate better passwords
* Upgrade required Warlock-Manager version to 2.2.13


## 2026-04-30

### Added

* Implement better logging throughout application
* Handle mismatching/incorrect user permissions on target user home


## 2026-04-26

### Changed

* Complete rewrite of the system for API 2.2

### Added

* Individual map backup/restore
* Better port conflict detection
* New TUI
* Mod support
* Custom map support
* Upgrade Proton to 10.34
* Add support for ASA API


## 2025-12-19

### Added

* Support for Lost Colony
* Per-map options to disable downloads
* Re-add option editing from CLI
* New Warlock features

### Changed

* Regression fix for Debian 12


## 2025-12-07

### Added

* Support custom installation directory
* Add support for some custom usecases of the installer
* Add support for --new-format as an argument to support Warlock
* Support for Warlock management system

### Changed

* Bump Proton to 10.25
* Fix for more flexible support for game options
* Backport 74.24 Steam fix into legacy start/stop scripts
* Fix support for JoinedSessionName (ini uses lowercase keys)


## 2025-11-05

### Fixed

* Broken Steam library in update 74.24

### Added

* Support for skipping firewall installation
* Add support for using completely custom session names


## 2025-11-02

### Added

* Support for uninstalling the server and all data
* Support for backup/start/stop maps as arguments to the management console
* Add support for custom modded maps

### Changed

* Refactor how options are handled in the management console


## 2025-11-01

### Added

* Support for Nitrado and Official server save formats
* Add support for customizing all player messages
* Add memory usage statistics to management console
* Cleanup and simplify startup reporting

### Fixed

* Fix for if mods library is missing


## 2025-10-19

### Added

* Displaying the name of the mods installed
* Backup/restore interface in management console
* Wipe player data functionality in management console

### Changed

* Assist user with troubleshooting by displaying the log on failure to start


## 2025-10-16

### Added

* Auto-updater checks
* Valguero map

### Fixed

* Support for Debian 13


## 2025-06-20

### Fixed

* `$GAME_USER` for non-standard installs - thanks techgo!

### Added

* Ragnarok support


## 2025-05-25

### Fixed

* Excessive question marks in options

### Added

* Expand exception handling in RCON for more meaningful error messages
* Checks to prevent changes while a game is running
* Auto-create steam `.ssh` directory for convenience
* Auto-create `Game.ini` for convenience


## 2025-05-05

### Added

* Backup and restore scripts


## 2025-05-02

### Added

* Checks for running out of memory
* Timeout to RCON for a more responsive UI when there are problems
* Modify map start logic to watch for memory issues in the first minute
* Update table listing to be Markdown compliant


## 2025-03-10

### Added

* Support for Discord integration on start/stop


## 2025-02-17

### Changed

* Switch to Proton 9.22

### Added

* Astraeos map
* Management script
* `--reset-proton` option
* `--force-reinstall` option
* Service upgrade check (when changing Proton versions)


## 2025-01-28

### Fixed

* Missing escape character


## 2024-12-20

### Changed

* Switch to UFW

### Added

* Extinction