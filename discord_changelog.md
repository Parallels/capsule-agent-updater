## What's Changed in capsule-agent-updater v0.1.11

Base version (stripped): 0.1.11
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

### Installation

Download the appropriate package for your platform from the [release assets](https://github.com/Parallels/capsule-agent-updater/releases/tag/v0.1.11).

### Links
- **Public Repository**: [github.com/Parallels/capsule-agent-updater](https://github.com/Parallels/capsule-agent-updater)
- **Monorepo Release**: [capsule-agent-updater-v0.1.11](https://github.com/Parallels-Corp/capsule-manager/releases/tag/capsule-agent-updater-v0.1.11)
