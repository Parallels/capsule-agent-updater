# Changelog - Capsule Agent Updater

All notable changes to the Capsule Agent Updater module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.14] - 2026-02-10



## [0.1.13] - 2026-02-09



## [0.1.12] - 2026-02-09

- Added a new dialog for confirming why we are asking for passwords
- Fixed an issue where we requested too many times for the root password
- Updated the updater to use channels
- Updated the capsule agent and updater install scripts
- Moved the capsule updater to also use the registry update endpoint  

## [0.1.11] - 2026-02-06

- Improved the way we deal with user feedback
- Added extra fields to the Capsules #118 
- Added the new marketplace application #116 
- Added a recovery for DNS issues with dnsmasq
- Added a new wait for the app to be ready
- Added better usage of urls when opening the page
- Added the new links to the marketplace
- Fixed an issue where Onboarding would failed for users that had used old capsules app
- Fixed an issue where the marketplace would crash if two users had an empty email
- Fixed issues with the users database constrains
- Updated install scripts to not overwrite the existing .env file
- Improved the design of the error dialog
- Fixed an issue where the error messages from the backend API would generate an error
- Enabled the debug messages in the log of the backend
- Fixed an issue in the install script that had the wrong variable name for the marketplace
- Fixed an issue in the search bar where it was not detecting empty strings and resetting the view

## [0.1.10] - 2025-12-03

- Removed some duplicated go routines
- Improved stability on the monitoring
- Fix some issues with telemetry
- Fixed some memory leaks

## [0.1.9] - 2025-10-20

- Modified release-capsule-marketplace-registry.yml to change environment descriptions and suffixes for canary and beta.
- Updated release-common-cleanup.yml to reflect new environment handling.
- Adjusted release-coordinator.yml to include canary and beta as options.
- Enhanced set-build-env.sh to propagate IS_CANARY and IS_BETA environment variables.
- Updated build.rs to embed IS_CANARY and IS_BETA into the build.
- Modified backend_manager.rs to handle service port dynamically and adjust health check URLs.
- Enhanced main.rs to set application configurations for canary and beta environments.
- Updated AppConfig interface to include isCanary and isBeta flags.
- Adjusted ConfigService to manage environment checks for canary and beta.
- Updated Makefiles for capsule-agent and capsule-agent-updater to include IS_BETA and IS_CANARY build flags.
- Enhanced telemetry to include environment and channel information.
- Added reset-application-hub.sh script for clearing user data and caches.
- Addressed a bug that could have stopped the way we started the app at first run
- Added a script to reset the application to the default to allow debugging

## [0.1.8] - 2025-10-17

## [0.1.7] - 2025-10-17

- Update codeowners
- Enhance markdownlint configuration
- Improve telemetry event naming
- Fixed missing telemetry from capsule-agent-updater
- Enhance issue templates and workflows to extract changelog content for releases #38

## [0.10.0] - 2024-08-26

- Initial release of Capsule Agent Updater
