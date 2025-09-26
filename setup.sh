#!/bin/sh
set -e

# Just set this to zero if you'd rather keep the build directory around.
DO_CLEANUP=1

# Set this to 1 to accept default prompts
ACCEPT_DEFAULTS=0

# Attempts to determine the number of cores in the CPU
# Source: https://gist.github.com/jj1bdx/5746298
CPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
[ -z "$CPUS" ] && CPUS=$(getconf NPROCESSORS_ONLN)
[ -z "$CPUS" ] && CPUS=$(ksh93 -c 'getconf NPROCESSORS_ONLN')
[ -z "$CPUS" ] && CPUS=1

while getopts 'yh' flag; do
	case "${flag}" in
		y) ACCEPT_DEFAULTS=1;;
		h)
			echo "Usage:"
			echo "    -h        Display this help message and exit."
			echo "    -y        Accept default prompts."
			exit 0;;
		\? ) exit 1;;
	esac
done

read_input() {
	if [ "$ACCEPT_DEFAULTS" -eq 1 ]; then
		set ""
	else
		read -r "$1"
	fi
}

# -----------------------------------------------------------------------------
# Deal with existing installations

# Make the user delete incomplete installations.
for f in Slippi-FM*; do
	if [ -d "${f}" ] && [ ! -d "$f/playback" ] && [ ! -d "$f/netplay" ]; then
		echo "[*] Found incomplete installation at $f/, deleting."
		rm -rf "$f" # is incomplete if bin/ doesn't exist
	fi
done
#if [ "$RESP" = "y" ] || [ "$RESP" = "Y" ]; then
#	echo "[*] Are you sure? This action is not reversible! (y/N) "
#	read -r RESP
#	if [ "$RESP" = "y" ] || [ "$RESP" = "Y" ] ; then
#		rm -rf Slippi-FM*/
#		echo "Sucessfully deleted all FM folders!"
#	fi
#else
#	echo "No changes made!"
#fi
echo ""

# -----------------------------------------------------------------------------
# Ask the user about udev rules, shortcuts, build options

SHORTCUTBOOL=1
echo "A desktop shortcut will be created after building Ishiiruka"
echo ""

# -----------------------------------------------------------------------------
# Ask the user which version of Slippi to install. Set $COMMITHASH to some
# commit associated with an Ishiiruka release

echo "[*] Please select a version of Slippi to install (1-4):"
echo "      1) Slippi r18"
echo "      2) Slippi r16"
echo "      3) Slippi r11"
echo "      4) Slippi r10"
echo "      *) Default: Slippi r18"
read_input RESP 1

COMMITHASH="1ef6f7bfc12e8566153054e6c964111da44f9125"
SLIPVER="r18"
		
echo "[*] User selected Slippi release $SLIPVER"


# -----------------------------------------------------------------------------
# Set options for targeting a particular release.

# This script assumes the existence of a `$r{SLIPVER}-config.tar.gz` in the 
# root of the installer repository which has the following structure:
#
#	- Sys/
#	- User/
#	- portable.txt
#
# Until we have to deal with managing multiple releases, just rely on this
# file having the current latest Dolphin configuration. Eventually, we need
# to sort out some process for building this config files (mostly by using
# `project-slippi/slippi-ssbm-asm` to compile Gecko codes, etc).

# For now, just deal with building r10 (make this user-configurable later).
DOLPHIN_REPO="https://github.com/project-slippi/Ishiiruka.git"
SCRIPT_REPO="https://github.com/project-slippi/Slippi-FM-installer"

# Path to the tarballs containing the Dolphin configuration files
PLAYBACK_CONFIG_TAR="slippi-${SLIPVER}-playback-config.tar.gz"
RECORDING_CONFIG_TAR="slippi-${SLIPVER}-recording-config.tar.gz"
PLAYBACK_CONFIG_URL="${SCRIPT_REPO}/raw/master/${PLAYBACK_CONFIG_TAR}"
RECORDING_CONFIG_URL="${SCRIPT_REPO}/raw/master/${RECORDING_CONFIG_TAR}"

echo "[*] Targeting Slippi release: $SLIPVER"
FOLDERNAME="Slippi-FM-${SLIPVER}"
if [ -d "$FOLDERNAME" ]; then
	echo "[*] FM Folder with same version found! Would you like to overwrite? (y/N) "
	
	if [ "y" = "y" ] || [ "$RESP" = "Y" ]; then
		echo "[*] Are you sure? This action is not reversible! (y/N) "
		
		if [ "y" = "y" ] || [ "$RESP" = "Y" ] ; then
			rm -r "$FOLDERNAME"
			echo "Sucessfully deleted $FOLDERNAME"
		else
			echo "[!] Quitting!"
			exit
		fi
	else
		echo "[!] Quitting!"
		exit
	fi
fi
echo ""

echo "[*] CPU Threads detected: $CPUS"
echo "[*] How many threads would you like to use to compile? "
echo "    (passed to make as -j flag, default: 1, range 1-$((CPUS)): "
read_input RESP

CPUS=1

echo "[*] Compiling with $CPUS thread(s)!"
echo ""


# -----------------------------------------------------------------------------
# Pull in Dolphin configuration from upstream FM and clone Slippi Ishiiruka

echo ""
mkdir "$FOLDERNAME" && cd "$FOLDERNAME"
echo "[*] Downloading recording config files..."
curl -LO# "$RECORDING_CONFIG_URL"
echo "[*] Extracting config files..."
tar -xzf "$RECORDING_CONFIG_TAR" --checkpoint-action='exec=printf "%d/410 records extracted.\r" $TAR_CHECKPOINT' --totals
rm "$RECORDING_CONFIG_TAR"

echo "[*] Cloning from $DOLPHIN_REPO ..."
git clone "$DOLPHIN_REPO" Ishiiruka
cd Ishiiruka
git checkout "$COMMITHASH"

# We need to make sure that users installing >r11 will SKIP THIS PATCH before
# calling CMAKE (the fix for Soundtouch should be in-tree for r11)
if [ "$SLIPVER" = "r10" ]; then
	echo "[*] Patching CMakeLists to use SoundTouch from Externals .."
	sed -i -e '741,746 s/^/#/'  -e '750 s/^/#/' CMakeLists.txt
fi


# -----------------------------------------------------------------------------
# Add config files into the build directory, then compile Ishiiruka and pull
# out the binary/configuration before deleting the tree

# Go into build directory
mkdir build && cd build

# Move files from config tarball into the Ishiiruka build directory
echo "[*] Moving Slippi/FM config files into the build directory"
mv ../../Binaries .
mv ../Data/dolphin-emu.png Binaries/

# Build Ishiiruka, yielding `dolphin-emu` binaries
cmake .. -DLINUX_LOCAL_DEV=true
make -j $CPUS -s

# Leave build directory (now prepared all config files and binaries)
cd ../..

# Pull out all build artifacts into a bin/ directory for the user
mv Ishiiruka/build/Binaries/ ./netplay/
mkdir ./netplay/Slippi

# We don't care about preserving things for r10 here because the launcher is
# only compatible starting with >r11
if [ "$SLIPVER" != "r10" ]; then
	# Have two directories - netplay and playback
	cp -R netplay/ playback

	# Pull out the playback configuration
	echo "[*] Downloading playback config files..."
	curl -LO# $PLAYBACK_CONFIG_URL
	tar -xzf "$PLAYBACK_CONFIG_TAR" --checkpoint-action='exec=printf "%d/410 records extracted.\r" $TAR_CHECKPOINT' --totals
	rm "$PLAYBACK_CONFIG_TAR"

	# Write the playback configuration to the folder
	cp -R Binaries/Sys playback/
	cp -R Binaries/User playback/
fi

if [ "$DO_CLEANUP" -eq 1 ]; then
	rm -rf ./Ishiiruka
	rm -rf ./Binaries/
fi

# -----------------------------------------------------------------------------
# Optionally create a shortcut/symlink

SYMLINK_NAME="slippi-${SLIPVER}-netplay"
if [ ! -e "${SYMLINK_NAME}" ]; then
	ln -s "$FOLDERNAME/netplay/dolphin-emu" "../${SYMLINK_NAME}"
	echo "[*] Wrote a symlink "
else
	echo "[*] Symlink ${SYMLINK_NAME} already exists"
fi

if [ "$SHORTCUTBOOL" -eq 1 ] && [ -d ~/.local/share/applications ]; then
	rm -f ~/.local/share/applications/slippi-fm-$SLIPVER.desktop
	rm -f ~/Desktop/slippi-fm-$SLIPVER.desktop
	touch ~/.local/share/applications/slippi-fm-$SLIPVER.desktop
	EXEPATH="$(pwd)/netplay/"
	FMNAME="Slippi FM $SLIPVER"
	echo "[Desktop Entry]
Type=Application
GenericName=Wii/GameCube Emulator
Comment=Slippi Ishiiruka $SLIPVER
Categories=Emulator;Game;
Icon=$EXEPATH/dolphin-emu.png
Version=$SLIPVER
Name=$FMNAME
Exec=$EXEPATH/dolphin-emu" | tee ~/.local/share/applications/slippi-fm-$SLIPVER.desktop > /dev/null
	cp ~/.local/share/applications/slippi-fm-$SLIPVER.desktop ~/Desktop
	chmod +x ~/Desktop/slippi-fm-$SLIPVER.desktop
	echo "[*] Created a desktop shortcut"
else
	echo "[!] .local folder not found, skipping desktop shortcut"
fi

echo "[!] All done! Run ./${SYMLINK_NAME} to run the latest installed version!" 
echo "    Alternatively, if you installed a desktop shortcut, you can go to"
echo "    Application > Games or your desktop and select the desired Slippi FM"
echo "    version." 
echo ""
echo "    If you've installed udev rules, make sure to unplug and replug your"
echo "    adapter before opening Dolphin!"
echo "" 
echo "    If you're using the Slippi Desktop App on this machine, make sure you" 
echo "    set the \"Playback Dolphin Path\" in the app settings to point at the"
echo "    newly created \"${FOLDERNAME}/playback/\" directory."
