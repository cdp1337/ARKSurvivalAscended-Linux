# scriptlet:_common/download.sh

##
# Update the installer from Github
#
function ark_update_installer() {
	local REPO="$1"
	local GITHUB_VERSION="$2"
	local TARGET="$3"

	if [ -z "$REPO" ] || [ -z "$GITHUB_VERSION" ] || [ -z "$TARGET" ]; then
		echo "update_installer: Missing required parameters!" >&2
		return 1
	fi

	TMP="$(mktemp)"
	local GITHUB_SOURCE="https://raw.githubusercontent.com/${REPO}/refs/tags/${GITHUB_VERSION}/dist/server-install-debian12.sh"
	if download "$GITHUB_SOURCE" "$TMP"; then
		echo "Downloaded new installer version $GITHUB_VERSION from github.com/${REPO}"
		mv "$TMP" "$TARGET"
		chmod +x "$TARGET"

		return 0
	else
		echo "update_installer: Failed to download installer version ${GITHUB_VERSION} from github.com/${REPO}" >&2
		return 1
	fi
}