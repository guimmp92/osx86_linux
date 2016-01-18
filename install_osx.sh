#!/bin/bash
export normal='tput sgr0'
export bold='setterm -bold'

export red='printf \033[00;31m'
export green='printf \033[00;32m'
export yellow='printf \033[00;33m'
export blue='printf \033[00;34m'
export purple='printf \033[00;35m'
export cyan='printf \033[00;36m'
export lightgray='printf \033[00;37m'
export lred='printf \033[01;31m'
export lgreen='printf \033[01;32m'
export lyellow='printf \033[01;33m'
export lblue='printf \033[01;34m'
export lpurple='printf \033[01;35m'
export lcyan='printf \033[01;36m'
export white='printf \033[01;37m'

rev=$(git log --pretty=oneline 2>/dev/null | wc -l)
if [ $rev -gt 0 ]; then
	program_revision="git r$rev"
else
	program_revision="git"
fi

if [ -z $really_verbose ]; then
	really_verbose=0
fi

if [ $really_verbose == 1 ]; then
	verbose="-v"
else
	verbose=""
fi
trap err_exit SIGINT

workdir=$(pwd -P)
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
cd $scriptdir

for i in $scriptdir/inc/*.sh; do
	source "$i"
done

function mediamenu(){
	mediamenu=1
	if [ $virtualdev == 1 ]; then
		if [ $nbd0_mapped -eq 0 ]; then
			$white; echo "Mapping $dev..."; $normal
			if ! qemu_map "nbd0" "$dev"; then
				err_exit "Can't map "$dev"\n"
			fi
		fi
		if [ ! -b "/dev/nbd0p1" ]; then
			err_exit "Corrupted image\n"
		fi
	fi

	if ! grep -q "/mnt/osx/target" /proc/mounts; then
		$yellow; echo "Mounting..."; $normal
		if [ $virtualdev -eq 1 ]; then
			mount_part "/dev/nbd0p1" "target"
		else
			$yellow; echo "Trying $dev..."; $normal
			if ! mount_part "$dev" "target" "silent"; then
				$yellow; echo "Trying ${dev}1..."; $normal
				mount_part "${dev}1" "target"
			fi
		fi
		if [ ! $? -eq 0 ]; then
			err_exit "Cannot mount target\n"
		else
			$lgreen; echo "Target Mounted"; $normal
		fi
		if [ ! -d /mnt/osx/target/Extra ]; then
			mkdir -p /mnt/osx/target/Extra/Extensions
		fi
		detect_osx_version
	fi
	echo "Working on "$dev""
	echo "Choose an operation..."
	echo "1  - Manage kexts"
	echo "2  - Manage chameleon Modules"
	echo "3  - Manage kernels"
	echo "4  - Reinstall / Update chameleon"
	echo "5  - Reinstall stock kernel"
	echo "6  - Install / Reinstall MBR Patch"
	echo "7  - Install / Reinstall Custom DSDT"
	echo "8  - Install / Reinstall SMBios"
	echo "9  - Erase Setup"
	echo "10 - Delete Kext Cache"
	echo "11 - Tweaks Menu"
	echo "0  - Exit"
	$white; printf "Choose an option: "; read choice; $normal
	case "$choice" in
		0)
			err_exit ""
			;;
		1)
			clear
			kextmenu
			mediamenu
			;;
		2)
			clear
			chammodmenu
			mediamenu
			;;
		3)
			clear
			kernelmenu
			mediamenu
			;;
		4)
			docheck_chameleon
			mediamenu
			;;
		5)
			do_kernel "target"
			mediamenu
			;;
		6)
			docheck_mbr
			pause; clear
			mediamenu
			;;
		7)
			docheck_dsdt
			pause; clear
			mediamenu
			;;
		8)
			docheck_smbios
			pause; clear
			mediamenu
			;;
		9)
			if ! cleanup; then
				err_exit ""
			fi
			if [ $virtualdev == 1 ]; then
				$lred; echo "WARNING: You are about to delete "$dev" content!"
				read -p "Are you really sure you want to continue? (y/n)" -n1 -r
				echo; $normal
				if [[ $REPLY =~ ^[Nn]$ ]];then
					err_exit ""
				fi
				rm "$dev"
				$lgreen; echo "$(basename $dev) succesfully deleted" ; $normal
				#else
				#	echo "Can't delete image"
			elif [ $virtualdev == 0 ]; then
				$lred; echo "WARNING: You are about to erase "$dev"!"
				read -p "Are you really sure you want to continue? (y/n)" -n1 -r
				echo; $normal
				if [[ $REPLY =~ ^[Nn]$ ]];then
					err_exit ""
				fi
					dd if=/dev/zero of="$dev" bs=512 count=1
					$lgreen: echo echo "$dev succesfully erased"; $normal
			fi
			err_exit ""
			;;
		10)
			do_remcache
			mediamenu
			;;
		11)
			clear
			tweakmenu
			mediamenu
			;;
		*)
			pause "Invalid option, press [enter] to try again"
			clear
			mediamenu
	esac
}

function tweakmenu(){
	local tweaks=($(find "$scriptdir/tweaks" -maxdepth 1 -type f -name "*.sh"))
	if [ ${#tweaks[@]} -eq 0 ]; then
		$lred; echo "No tweak to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a tweak to apply: "
	$white; echo "0 - Return to main menu"; $normal

	for i in ${!tweaks[@]}; do
		local name=$(grep tweakname= ${tweaks[$i]} | grep -o "=.*" | sed 's|[="]||g')
		echo $((i + 1)) - ${name}
	done
	$white; echo "Choose a tweak to apply"; $normal
	read choice
	if [ -z $choice ] || [ $choice -lt 0 ] || [ $choice -gt ${#tweaks[@]} ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		tweakmenu
	elif [ $choice -eq 0 ]; then
		clear
		mediamenu
	else
		clear
		local tweak=${tweaks[$((choice-1))]}
		$yellow; echo "Applying ${tweak}..."; $normal
		bash "${tweak}"
	fi
	$lgreen; echo "Done!"; $normal
	tweakmenu
}

function kextmenu(){
	kexts=$(find "$kextdir" -maxdepth 1 -type d -name "*.kext" | wc -l)
	if [ $kexts == 0 ]; then
		$lred; echo "No kext to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a kext to Install / Reinstall: "
	local k
	local eskdir=$(echo "$kextdir" | sed 's/\ /\\\//g;s/\//\\\//g')
	$white; echo "0 - Return to main menu"; $normal
	for k in `seq $kexts`; do
		local option=$(find "$kextdir" -maxdepth 1 -type d -not -name ".gitignore" -name "*.kext" | sed "s/$eskdir\///g" | sed -n "$k"p)
			eval kext$k="$option"
			if [ -d "/mnt/osx/target/Extra/Extensions/"$option"" ]; then
				printf "[*]\t$k - $option\n"
			else
				printf "[ ]\t$k - $option\n"
			fi
	done
	$white; echo "Choose a kext to install/uninstall"; $normal
	read choice
	local name="kext$choice"
	if [ "$choice" == "0" ]; then
		clear
		mediamenu
	fi
	if [ -z "${!name}" ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		kextmenu
	else
	clear
		if [ -d "/mnt/osx/target/Extra/Extensions/${!name}" ]; then
			$yellow; echo "Removing ${!name}..."; $normal
			rm -R "/mnt/osx/target/Extra/Extensions/${!name}"
		else
			$yellow; echo "Installing ${!name}..."; $normal
			cp -R "$kextdir/${!name}" /mnt/osx/target/Extra/Extensions/
			chown -R 0:0 "/mnt/osx/target/Extra/Extensions/${!name}"
			chmod -R 755 "/mnt/osx/target/Extra/Extensions/${!name}"
		fi
	fi
	$lgreen; echo "Done!"; $normal
	kextmenu
}

function chammodmenu(){
	modules=$(find "$scriptdir/chameleon/Modules" -maxdepth 1 -type f -name "*.dylib" | wc -l)
	if [ $modules == 0 ]; then
		$lred; echo "No module to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a module to Install / Reinstall: "
	local m
	local esmdir=$(echo "$scriptdir/chameleon/Modules" | sed 's/\ /\\\//g;s/\//\\\//g')
	$white; echo "0 - Return to main menu"; $normal
	for m in `seq $modules`; do
		local option=$(find "$scriptdir/chameleon/Modules" -maxdepth 1 -type f -not -name ".gitignore" -name "*.dylib" | sed "s/$esmdir\///g" | sed -n "$m"p)
			eval module$m="$option"
			if [ -f "/mnt/osx/target/Extra/Modules/"$option"" ]; then
				printf "[*]\t$m - $option\n"
			else
				printf "[ ]\t$m - $option\n"
			fi
	done
	$white; echo "Choose a module to install/uninstall"; $normal
	read choice
	local name="module$choice"
	if [ "$choice" == "0" ]; then
		clear
		mediamenu
	fi
	if [ -z "${!name}" ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		chammodmenu
	else
	clear
		if [ -f "/mnt/osx/target/Extra/Modules/${!name}" ]; then
			$yellow; echo "Removing ${!name}..."; $normal
			rm "/mnt/osx/target/Extra/Modules/${!name}"
		else
			$yellow; echo "Installing ${!name}..."; $normal
			cp "$scriptdir/chameleon/Modules/${!name}" /mnt/osx/target/Extra/Modules/
			chmod -R 755 "/mnt/osx/target/Extra/Modules/${!name}"
		fi
	fi
	$lgreen; echo "Done!"; $normal
	chammodmenu
}

function kernelmenu(){
	kernels=$(find "$kerndir" -maxdepth 1 -type f -not -name ".gitignore" | wc -l)
	if [ $kernels == 0 ]; then
		$lred; echo "No kernel to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a kernel to Install / Reinstall: "
	local k
	local eskdir=$(echo "$kerndir" | sed 's/\ /\\\//g;s/\//\\\//g')
	$white; echo "0 - Return to main menu"; $normal
	for k in `seq $kernels`; do
		local option=$(find "$kerndir" -maxdepth 1 -type f -not -name ".gitignore" | sed "s/$eskdir\///g" | sed -n "$k"p)
			eval kern$k="$option"
			if [ -f "/mnt/osx/target/"$option"" ]; then
				printf "[*]\t$k - $option\n"
			else
				printf "[ ]\t$k - $option\n"
			fi
	done
	$white; echo "Choose a kernel to install/uninstall"; $normal
	read choice
	local name="kern$choice"
	if [ "$choice" == "0" ]; then
		clear
		mediamenu
	fi
	if [ -z "${!name}" ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		kernelmenu
	else
	clear
		if [ -f "/mnt/osx/target/${!name}" ]; then
			if [ "${!name}" == "mach_kernel" ]; then #stock kernel
				read -p "Warning, you are about to overwrite the default Kernel. Do you want to back it up to \"apple_kernel\"? (yes/no/abort)" -n1 -r
				echo
				if [[ $REPLY =~ ^[Aa]$ ]];then
					kernelmenu
				elif [[ $REPLY =~ ^[Yy]$ ]];then
					$yellow; echo "Backing up mach_kernel..."; $normal
					mv /mnt/osx/target/mach_kernel /mnt/osx/target/apple_kernel
					$yellow; echo "Copying new mach_kernel..."; $normal
					cp $verbose "$kerndir/${!name}" /mnt/osx/target/
					chmod 755 "/mnt/osx/target/${!name}"
				fi
			else #alternative kernel name, we can delete
				$yellow; echo "Removing ${!name}..."; $normal
				rm $verbose "/mnt/osx/target/${!name}"
			fi
		else
			$yellow; echo "Installing ${!name}..."; $normal
			cp $verbose "$kerndir/${!name}" /mnt/osx/target/
			chmod 755 "/mnt/osx/target/${!name}"
		fi
	fi
	$lgreen; echo "Done!"; $normal
	kernelmenu
}

function vdev_check(){
	echo "Virtual HDD Image Mode"
	virtualdev=1
	if ! check_command 'qemu-nbd' == 0; then
		err_exit ""
	fi

 	# which partition holds the image
	local file_info
	if [ -f "$1" ]; then
		file_info=$(df -TP "$1")
	else
		touch "$1"
		file_info=$(df -TP "$1")
		rm "$1"
	fi
	local fstype=$(echo "${file_info}" | awk '/^\/dev/ {print $2}')
	local mountdev=$(echo "${file_info}" | awk '/^\/dev/ {print $1}')
	if [ ! -b "${mountdev}" ]; then
		err_exit "${mountdev} is not a valid block device\n"
	fi
	local isRO=$(isRO "${mountdev}"; echo $?)
	if [ $isRO -eq 1 ]; then
		err_exit "${mountdev} is mounted in R/O mode!\n"
	fi
	if [ "${fstype}" == "ntfs" ] && [ "${fstype}" == "fuseblk" ]; then
		$lred; echo "WARNING, YOUR DMG IS STORED ON A FUSE FILESYSTEM!, READ/WRITE OPERATIONS MAY BE SLOW"
		echo "A non-FUSE FS is recommended"
		read -p "Are you sure you want to continue? (y/n)" -n1 -r
		echo; $normal
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit ""
		fi
	fi
	if [ ! -f "$1" ] && [ "$dextension" == ".vdi" ]; then
		vbhdd=1; format=VDI
	elif [ ! -f "$1" ] && [ "$dextension" == ".vhd" ]; then
		vbhdd=1; format=VHD
	elif [ ! -f "$1" ] && [ "$dextension" == ".vmdk" ]; then
		vbhdd=1; format=VMDK
	elif [ -f "$file" ] && [ -z "$dev" ]; then
		dev=$file
		clear; mediamenu
		#err_exit "$1 already exists. Exiting\n"
	#else
	#	err_exit "Unknown Error!\n"
	fi
	if [ "$size" == "" ] || [ "$size" == " " ] || [ -z $size ]; then
		if [ $mkrecusb == 1 ]; then
			size=$((400 * 1024 * 1024)) #400
		else
			size=$((10 * 1024 * 1024 * 1024)) #10gb
		fi
	fi
	check_space "$mountdev" "$size" 1
	isdev=$(echo "$1" | grep -q "/dev/"; echo $?)
	if [ $isdev == 0 ]; then
		err_exit "Something wrong, not going to erase $dev\n"
	fi
}

function do_finalize(){
	do_kexts
	do_remcache
	do_kextperms
	docheck_chameleon
	docheck_smbios
	docheck_dsdt
}

function do_preptarget(){
	if [ $virtualdev -eq 1 ] && [ $vbhdd -eq 0 ]; then
		$yellow; echo "Creating Image..."; $normal
		if [ -f "$dev" ]; then
			$lred; read -p "Image $dev already exists. Overwrite? (y/n)" -n1 -r
			echo; $normal
			if [[ $REPLY =~ ^[Nn]$ ]];then
				err_exit ""
			fi
		fi
		dd if=/dev/zero bs=1 of="$dev" seek="$size" count=0
		if [ ! $? == 0 ]; then
			err_exit "Error during image creation\n"
		fi
	elif [ $virtualdev -eq 1 ] && [ $vbhdd -eq 1 ]; then
			if ! check_command 'vboxmanage' == 0; then
				err_exit ""
			fi
			vboxmanage createhd --filename "$dev" --sizebyte $size --format "$format" --variant Standard
			if [ ! $? == 0 ]; then
				err_exit "Error during Virtual Hard Disk Creation\n"
			fi
	elif [ $virtualdev -eq 0 ] && [ $vbhdd -eq 0 ]; then
		if [[ $dev = *[0-9] ]]; then
			usage
			err_exit "You must specify the whole device, not a single partition!\n"
		fi
		for part in $dev*[0-9]; do
			echo "Part: $part"
			if grep -q "$part" /proc/mounts; then
				umount "$part"
			fi
			if grep -q "$part" /proc/mounts; then
				err_exit "Couldn't unmount "$part"\n"
			fi
		done
		isRO=$(isRO "$dev")
		echo "isRemovable = $isRO"
		if [ $isRO -eq 0 ]; then
			$lred; echo "WARNING, "$dev" IS NOT A REMOVABLE DEVICE!"
			echo "ARE YOU SURE OF WHAT YOU ARE DOING?"
			read -p "Are you REALLY sure you want to continue? (y/n)" -n1 -r
			echo; $normal
			if [[ $REPLY =~ ^[Nn]$ ]];then
				err_exit "Exiting\n"
			fi
		fi

		$lred; echo "WARNING, ALL THE CONTENT OF "$dev" WILL BE LOST!"
		read -p "Are you sure you want to continue? (y/n)" -n1 -r
		echo; $normal
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit "Exiting\n"
		fi
	else
		err_exit "Unknown Operation Mode\n"
	fi

	if [ $virtualdev -eq 1 ]; then
		chmod 666 "$dev"
		chown "$SUDO_USER":"$SUDO_USER" "$dev"
	fi

	if [ $vbhdd -eq 1 ]; then
		echo "Mapping virtual dev with qemu..."
		qemu-nbd -d /dev/nbd0 &>/dev/null
		if ! qemu-nbd -c /dev/nbd0 "$dev"; then
			err_exit "Error during nbd mapping\n"
		fi
	fi

	echo "Creating Partition Table on $dev..."
	if [ $vbhdd -eq 0 ]; then
		parted -a optimal "$dev" mklabel msdos
	else
		parted -a optimal "/dev/nbd0" mklabel msdos
	fi

	if [ ! $? -eq 0 ]; then
		err_exit "Error during partition table creation\n"
	fi

	echo "Creating new Primary Active Partition on $dev"
	if [ $vbhdd -eq 0 ]; then
		parted -a optimal "$dev" --script -- mkpart primary hfs+ "1" "-1"
	else
		parted -a optimal "/dev/nbd0" --script -- mkpart primary hfs+ "1" "-1"
	fi
	if [ ! $? -eq 0 ]; then
		err_exit "Error: cannot create new partition\n"
	fi
	if [ $vbhdd -eq 0 ]; then
		parted -a optimal "$dev" print
		parted -a optimal "$dev" set 1 boot on
	else
		parted -a optimal "/dev/nbd0" print
		parted -a optimal "/dev/nbd0" set 1 boot on
	fi
	sync
	if [ $virtualdev -eq 1 ] && [ $vbhdd -eq 0 ]; then
		if [ ! $nbd0_mapped -eq 1 ]; then
			echo "Mapping virtual dev with qemu..."
			if ! qemu_map "nbd0" "$dev"; then
				err_exit "Error during nbd mapping\n"
			fi
		fi
	fi

	$lyellow; echo "Formatting partition as HFS+"; $normal
	if [ $virtualdev -eq 1 ]; then
		mkfs.hfsplus /dev/nbd0p1 -v "smx_installer"
	else
		mkfs.hfsplus "${dev}1" -v "smx_installer"
	fi
	if [ ! $? -eq 0 ]; then
		err_exit "Error during HFS+ formatting\n"
	fi

	if [ $virtualdev -eq 1 ]; then
		mount_part "/dev/nbd0p1" "target"
	else
		mount_part "${dev}1" "target"
	fi
	if [ ! $? -eq 0 ]; then
		err_exit "Cannot mount target\n"
	fi

	if [ ! -d /mnt/osx/target/Extra ]; then
		mkdir -p /mnt/osx/target/Extra/Extensions
	fi
}

function do_kexts(){
	local kexts=$(find "$kextdir" -maxdepth 1 -type d -name "*.kext" | wc -l)
	if [ $kexts == 0 ]; then
		$lred; echo "No kext to install"; $normal
	else
		$ylellow; echo "Installing kexts in \"extra_kexts\" directory"; $normal
		kextdir="$scriptdir/extra_kexts"
		for kext in $kextdir/*.kext; do
		echo " Installing $(basename $kext)..."
		cp -R $verbose "$kext" /mnt/osx/target/Extra/Extensions/
		chown -R 0:0 "/mnt/osx/target/Extra/Extensions/$(basename $kext)"
		chmod -R 755 "/mnt/osx/target/Extra/Extensions/$(basename $kext)"
		done
		sync
	fi
}

function docheck_smbios(){
	if [ -f "$scriptdir/smbios.plist" ]; then
		cp $verbose "$scriptdir/smbios.plist" /mnt/osx/target/Extra/smbios.plist
	else
		$lyellow; echo "Skipping smbios.plist, file not found"; $normal
		if [[ ! "$osver" =~ "10.6" ]]; then
			$lred; echo "Warning: proper smbios.plist may be needed"; $normal
		fi
	fi
}

function docheck_dsdt(){
	if [ -f "$scriptdir/DSDT.aml" ]; then
		cp $verbose "$scriptdir/DSDT.aml" /mnt/osx/target/Extra/DSDT.aml
	else
		$lred; echo "DSDT.aml not found!"; $normal
		$lyellow; echo "Using system stock DSDT table"; $normal
	fi
}

function docheck_chameleon(){
	if  [ -f  "$scriptdir/chameleon/boot1h" ] && [ -f  "$scriptdir/chameleon/boot" ]; then
		do_chameleon
	else
		$lred; echo "WARNING: Cannot install Chameleon, critical files missing"
		echo "Your installation won't be bootable"; $normal
	fi
}

function docheck_mbr(){
	if [ -d "$scriptdir/osinstall_mbr" ] &&
		[ -f "$scriptdir/osinstall_mbr/OSInstall.mpkg" ] &&
		[ -f "$scriptdir/osinstall_mbr/OSInstall" ]
		then
			if check_mbrver; then
				do_mbr
			fi
		else
			$lred; echo "Mbr patch files missing!"; $normal
		fi
}

function check_mbrver(){
	if [ -d "$scriptdir/tmp/osinstall_mbr" ]; then rm -r "$scriptdir/tmp/osinstall_mbr"; fi
	echo "Checking patch version..."
	extract_pkg "$scriptdir/osinstall_mbr/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/p"
	if [ -f "/mnt/osx/target/Packages/OSInstall.mpkg" ]; then # esd
		echo "Checking original version..."
		extract_pkg "/mnt/osx/target/Packages/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/o"
	else #target
		echo "Checking original version..."
		extract_pkg "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/o"
	fi
	local origver=$(cat "$scriptdir/tmp/osinstall_mbr/o/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local origbuild=$(cat "$scriptdir/tmp/osinstall_mbr/o/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
	local patchver=$(cat "$scriptdir/tmp/osinstall_mbr/p/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local patchbuild=$(cat "$scriptdir/tmp/osinstall_mbr/p/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
	if [ ! "$patchver" == "$origver" ] || [ ! "$patchbuild" == "$origbuild" ]; then
		$lred "WARNING: NOT APPLYING MBR PATCH"
		echo "INCOMPATIBLE VERSIONS"
		$lyellow
		printf "Original:\t$origbuild\nPatch:\t\t$patchbuild\n"
		$normal
		return 1
	else
		return 0
	fi
}

function do_remcache(){
	$lyellow; echo "Deleting Kext Cache..."; $normal
	if [ -f /mnt/osx/target/System/Library/Caches/kernelcache ]; then
		rm /mnt/osx/target/System/Library/Caches/kernelcache
	fi
}

function do_kextperms(){
	$lyellow; echo "Repairing Kext Permissions..."; $normal
	for path in System/Library/Extensions Extra/Extensions; do
		if [ -d /mnt/osx/target/${path} ]; then
			$yellow; echo "/${path}..."; $normal
			find "/mnt/osx/target/${path}" -type d -name "*.kext" -print0 | while read -r -d '' kext; do
				#echo "Fixing ... $kext"
				chmod -R 755 "$kext"
				chown -R 0:0 "$kext"
			done
		fi
	done
	$lgreen; echo "Done"; $normal
}

function do_mbr(){
	$lyellow; echo "Patching Installer to support MBR"; $normal
	cp $verbose "$scriptdir/osinstall_mbr/OSInstall.mpkg" "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg"
	cp $verbose "$scriptdir/osinstall_mbr/OSInstall" "/mnt/osx/target/System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework/Versions/A/OSInstall"
}

function do_clover(){
	local target_mbr
	local target_pbr
	if [ $virtualdev -eq 1 ]; then
		target_mbr="/dev/nbd0"
		target_pbr="${target_mbr}p1"
	else
		target_mbr="${dev}"
		target_pbr="${dev}1"
	fi

	$lyellow; echo "Installing clover..."; $normal
	if [ -f "${scriptdir}/clover/boot0ss" ]; then
		$yellow; echo "Flashing Master boot record..."; $normal
		dd if="${scriptdir}/clover/boot0ss" of="${target_mbr}"
	fi
	if [ -f "${scriptdir}/clover/boot1f32alt" ]; then
		$yellow; echo "Flashing Partition boot record..."; $normal
		dd if="${target_pbr}" count=1 bs=512 of="${scriptdir}/tmp/origbs"
		cp $verbose "${scriptdir}/clover/boot1f32alt" "${scriptdir}/tmp/newbs"
		dd if="${scriptdir}/tmp/origbs" of="${scriptdir}/tmp/newbs" skip=3 seek=3 bs=1 count=87 conv=notrunc
		dd if="${scriptdir}/tmp/newbs" of="${target_pbr}" bs=512 count=1
	fi
}

function do_chameleon(){
	$lyellow; echo "Installing chameleon..."; $normal
	cp $verbose "$scriptdir/chameleon/boot" /mnt/osx/target/
	sync

	if [ -d "$scriptdir/chameleon/Themes" ]; then
		$yellow; echo "Copying Themes..."; $normal
		cp -R "$scriptdir/chameleon/Themes" "/mnt/osx/target/Extra/"
	fi
	if [ -d "$scriptdir/chameleon/Modules" ]; then
		$yellow; echo "Copying Modules..."; $normal
		cp -R "$scriptdir/chameleon/Modules" "/mnt/osx/target/Extra/"
	fi
	sync

	$yellow; echo "Flashing boot record..."; $normal
	if [ ! -f  "$scriptdir/chameleon/boot0" ]; then
		$lred; echo "WARNING: MBR BootCode (boot0) Missing."
		echo "Installing Chameleon on Partition Only"; $normal
	else
		local do_instMBR=0
		if [ -z $chameleonmbr ]; then
			read -p "Do you want to install Chameleon on MBR? (y/n)" -n1 -r
			echo
			if [[ $REPLY =~ ^[Yy]$ ]]; then do_instMBR=1; fi
		elif [ "$chameleonmbr" == "true" ]; then do_instMBR=1; fi
	fi
	if [ $virtualdev -eq 1 ]; then
		if [ $do_instMBR -eq 1 ]; then
			dd bs=446 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="/dev/nbd0"
			sync
		fi
		dd if="$scriptdir/chameleon/boot1h" of="/dev/nbd0p1"
		sync
	else
		if [ $do_instMBR -eq 1 ]; then
			dd bs=446 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="$dev"
		fi
		dd if="$scriptdir/chameleon/boot1h" of="${dev}1"
	fi
	sync
}

function check_space {
	local device=$1
	local minimum=$2
	local strict=$3
	freespace=$(( $(df "$device" | sed -n 2p | awk '{print $4}') * 1024))
	printf "FreeSpace:\t$freespace\n"; printf "Needed:\t\t$minumum\n"
	if [ $freespace -ge $minimum ]; then
		return 0
	else
		if [ $strict -eq 1 ]; then
			err_exit "Not enough free space\n"
		else
			return 1
		fi
	fi
}

function check_commands {
	$lyellow; echo "Checking Commands..."
	$normal
	#if [ $commands_checked == 1 ]; then
		#add checks for other commands after the initial check
	#	echo &>/dev/null
	#else
		commands=('dialog' 'grep' 'tput' 'dd' 'sed' 'parted' 'awk' 'mkfs.hfsplus' 'wget' 'dirname' 'basename' 'parted' 'pidof' 'gunzip' 'bunzip2' 'cpio')
	#fi
	for command in "${commands[@]}"; do
		if ! check_command $command == 0; then
			$normal
			err_exit ""
		fi
		$normal
	done
}

function find_cmd {
	# Command to look for
	cmdvar=$1
	# Preferred search dir
	cmd_dir=$2
	# Full command name (optional)
	cmd=$3

	local cmd_path
	if [ ! -z "${cmd}" ]; then
		cmd_path="${cmd_dir}/${cmd}"
	elif [ ! -z "${cmd_dir}" ]; then
		cmd_path="${cmd_dir}/${cmdvar}"
	else
		cmd_path="$(type -P "${cmdvar}")"
	fi

	# Store the command path in the command-named variable (ex xar -> $xar)
	if [ -e "${cmd_path}" ]; then
		eval ${cmdvar}=${cmd_path}
	else
		unset ${cmdvar}
	fi

	#echo "Arg   --> $cmd"
	#echo "Var   --> ${cmd}"
	#echo "Value --> ${!cmd}"
}

function check_command {
	local command=$1
	echo $command | grep -q '\$'
	if [ $? == 0 ]; then
		command_name=$(echo $command | sed -e 's/\$//g')
		command=${!command_name}
	else
		command_name=$command
	fi

	type -P "$command" &>/dev/null
	local cmdstat=$?

	if [ -z "$command" ]; then
		cmdstat=1
	fi
	$lcyan; printf "$command_name: "
	if [ $cmdstat == 0 ]; then
		$lgreen; printf "Found\n"; $normal
		return 0
	elif [ $cmdstat == 1 ]; then
		$lred; printf "Not Found\n"; $normal
		return 1
	else
		$lightgray; printf "Unknown Error\n"; $normal
		return 2
	fi
}

function cleanup() {
	sync
	if [ ! "${scriptdir}/tmp" == "/tmp" ] && [ -d "${scriptdir}/tmp" ]; then
		rm -r "${scriptdir}/tmp"
	fi

	qemu_umount_all
	qemu_unmap_all

	if grep -q "/mnt/osx/target" /proc/mounts; then
	 	umount /mnt/osx/target
		if grep -q "/mnt/osx/target" /proc/mounts; then
			$lred; echo "ERROR: Can't unmount target!"; $normal
		fi
	fi

	if [ -b /dev/nbd0 ]; then
		if ! rmmod nbd; then
			$lred; echo "WARNING: Cannot unload nbd"; $normal
		fi
	fi

	local result=0
	if [ -d /mnt/osx ]; then
		for mountpoint in base esd target; do
			if [ -d "/mnt/osx/${mountpoint}" ] && isEmpty "/mnt/osx/${mountpoint}"; then
				rmdir "/mnt/osx/${mountpoint}"
			else
				result=1
			fi
		done

		if isEmpty "/mnt/osx"; then
			rmdir /mnt/osx
		else
			$lyellow; echo "Some partitions couldn't be unmounted. Check what's accessing them and unmount them manually"; $normal
			result=1
		fi
	fi

	return $result
}

function usage(){
	echo "Osx Installer/Utilities for Linux by SMX"
	printf "$0 [dmgfile] [dev]\t\tConverts and install a dmg to a device\n"
	printf "$0 [dmgfile] [img file]\t\tConverts and install and create an img file\n"
	printf "$0 [dmgfile] [vdi/vmdk/vhd]\tConverts and install and create a virtual hard disk\n"
	printf "$0 [img file/vdi/vmdk/vhd]\tOpen the setup management/tweak menu\n"
	printf "$0 [pkg/mpkg] [destdir]\t\tExtract a package to destdir\n"
	printf "$0 [dev]\t\t\t\tShow Management Menu for setup media\n"
	printf "$0 --mkchameleon [dev]\t\tMakes chameleon rescue USB\n"
	printf "Management menu:\n"
	printf "\t-Install/Remove extra kexts\n"
	printf "\t-Install/Remove chameleon Modules\n"
	printf "\t-Install/Remove extra kernels\n"
	printf "\t-Install/Reinstall chameleon\n"
	printf "\t-Install/Reinstall mbr patch\n"
	printf "\t-Install/Reinstall custom smbios\n"
	printf "\t-Install/Reinstall custom DSDT\n"
	printf "\t-Apply tweaks/workarounds\n"
	printf "\t-Erase the whole setup partition\n"
}

function main(){
	if [ "$1" == "guictl" ]; then
		"$2" "${*:2}"
		return 0
	fi

	$lgreen; printf "OSX Install Media Maker by "
	$lyellow; printf "S"
	$lblue; printf "M"
	$lpurple; printf "X\n"
	$normal

	echo "Version: $program_revision"

	# Export APIs for tweaks
	export -f do_remcache
	export -f do_kextperms
	export -f docheck_smbios
	export -f docheck_dsdt
	export -f docheck_mbr
	export -f mount_part
	export -f check_commands
	mediamenu=0

	if [ -z $SUDO_USER ]; then
		SUDO_USER="root"
	fi

	if [ $# == 0 ] ||
	[ "$1" == "-h" ] ||
	[ "$1" == "--help" ] ||
	[ "$1" == "help" ] ||
	[ "$1" == "?" ] ||
	[ "$1" == "/?" ]
	then
		$white; usage; $normal
		err_exit ""
	fi

	file="$1"

	name=$(basename "$1" 2>/dev/null) #input
	extension=".${name##*.}"
	filename="${name%.*}"

	dname=$(basename "$2") #output
	dextension=".${dname##*.}"
	dfilename="${dname%.*}"

	find_cmd "xar" "${scriptdir}/xar_bin/bin"
	docheck_xar
	find_cmd "dmg2img" "${scriptdir}/dmg2img_bin/usr/bin"
	docheck_dmg2img
	find_cmd "pbzx" "${scriptdir}"
	docheck_pbzx
	find_cmd "kconfig_mconf" "${scriptdir}/kconfig_bin/bin" "kconfig-mconf"
	docheck_kconfig


	$green
	echo "== External Dependencies =="
	$white
	echo "xar           => ${xar}"
	echo "dmg2img       => ${dmg2img}"
	echo "pbzx          => ${pbzx}"
	echo "kconfig-mconf => ${kconfig_mconf}"
	$normal
	if [ ! -f "${xar}" ] ||
	[ ! -f "${dmg2img}" ] ||
	[ ! -f "${pbzx}" ] ||
	[ ! -f "${kconfig_mconf}" ]
	then
		err_exit "Invalid dependencies, cannot continue!\n"
	fi

	if [ "$extension" == ".pkg" ] || [ "$extension" == ".mpkg" ]; then #./install_osx.sh [file.pkg/mpkg]
		if [ -z "$2" ]; then #no dest dir
			usage
			err_exit "Invalid Destination Folder\n"
		fi
		extract_pkg "$1" "$2"
		cleanup
		exit 0
	fi

	load_config

	kextdir="${scriptdir}/extra_kexts"
	kerndir="${scriptdir}/kernels"
	filepath="$( cd "$( dirname "$1" 2>/dev/null)" && pwd -P)"
	devpath="$( cd "$( dirname "$2" 2>/dev/null)" && pwd -P)"

	if grep -q "/mnt" /proc/mounts; then
		$lyellow; echo "Unmounting /mnt..."; $normal
		umount /mnt
		if grep -q "/mnt" /proc/mounts; then
			err_exit "/mnt busy, cannot continue\n"
		fi
	fi
	# Create working dir
	if [ ! -d /mnt/osx ]; then mkdir -p /mnt/osx; fi
	# Create ESD mountpoint
	if [ ! -d /mnt/osx/esd ]; then mkdir /mnt/osx/esd; fi
	# Create BaseSystem mountpoint
	if [ ! -d /mnt/osx/base ]; then mkdir /mnt/osx/base; fi
	# Create target mountpoint
	if [ ! -d /mnt/osx/target ]; then mkdir /mnt/osx/target; fi

	nbd0_mapped=0
	nbd1_mapped=0
	nbd2_mapped=0

	do_init_qemu

	dev="$2"
	size=$3 #for img creation

	virtualdev=0
	vbhdd=0

	if [[ ! "$OSTYPE" == linux* ]]; then
		err_exit "This script can only be run under Linux\n"
	fi

	if [ ! ${EUID} -eq 0 ]; then
	   err_exit "This script must be run as root\n"
	fi

	mkrecusb=0
	if [ -b "$1" ] &&
		[ ! -f "$1" ] &&
		[ ! -d "$1" ] &&
		[ -z "$2" ] &&
		[ -z "$3" ]
	then #./install_osx.sh [dev]
		dev="$1"
		mediamenu
	elif [ -f "$1" ] && [ -z "$2" ] && [ -z "$3" ]; then #./install_osx.sh [file]
		if [ "$extension" == ".dmg" ]; then #./install_osx.sh [file.dmg]
			usage
			err_exit "You must specify a valid target drive or image\n"
		elif [ "$extension" == ".img" ] ||
			[ "$extension" == ".hdd" ] ||
			[ "$extension" == ".vhd" ] ||
			[ "$extension" == ".vdi" ] ||
			[ "$extension" == ".vmdk" ]
		then #./install_osx.sh [file.img]
			dev="$1"
			virtualdev=1
			mediamenu
		fi
	elif [ ! -b "$1" ] &&
		[ ! -f "$1" ] &&
		[ ! -d "$1" ] &&
		[ -z "$2" ] &&
		[ -z "$3" ]
	then
		err_exit "No such device\n"
	fi

	if [ ! "$extension" == ".dmg" ] && [ ! "$extension" == ".img" ]; then
			if [ "$1" == "--mkchameleon" ]; then
				mkrecusb=1
				bootloader="chameleon"
			else
				usage
				err_exit "Invalid file specified\n"
			fi
	fi

	if [ -z "${dev}" ]; then
		usage
		err_exit "You must specify a valid target drive or image\n"
	fi

	if [ ! -b "${dev}" ]; then
		if [ "$dextension" == ".img" ] ||
			[ "$dextension" == ".hdd" ] ||
			[ "$dextension" == ".vhd" ] ||
			[ "$dextension" == ".vdi" ] ||
			[ "$dextension" == ".vmdk" ]
		then
			vdev_check "$2" #switch to Virtual HDD mode & check
		fi
	fi

	if [ -z $commands_checked ]; then	commands_checked=0; fi
	if [ $commands_checked == 0 ]; then
		check_commands	#Check all required commands exist
		commands_checked=1
		export commands_checked
	fi
	if [[ $1 == "/dev/sr[0-9]" ]]; then
		$lgreen; echo "CD Source Device Detected"; $normal
		if [ -z $2 ] || [ -d "$2" ] || [ "$2" == "" ]; then
			err_exit "You must specify a valid destination to create an img file\n"
		elif [ -f "$2" ]; then
			err_exit "$2 already exists\n"
		else
			$yellow; echo "Img creation is in progress..."
			echo "The process may take some time"; $normal
			if [ ! -d "$(dirname "$2")" ]; then
				mkdir -p "$(dirname "$2")"
			fi
			if [ ! -d "$(dirname "$2")" ]; then
				err_exit "Can't create destination folder\n"
			fi
			dd if="$1" of="$2"
			watch -n 10 kill -USR1 `pidof dd`
		fi
	fi

	do_preptarget
	if [ $mkrecusb -eq 1 ]; then
		do_finalize
		err_exit ""
	fi

	outfile=""$filepath/$filename".img"
	if [ ! -e "$outfile" ]; then
		echo "Converting "$file" to img..."
		$dmg2img "$file" "$outfile"
	#check_err=$(cat /tmp/dmg2img.log | grep -q "ERROR:"; echo $?)
	#if [ ! $? == 0 ] || [ ! -f "$outfile" ] || [ $check_err == 0 ]; then
	if [ ! $? == 0 ] || [ ! -f "$outfile" ]; then
		rm "$outfile"
		err_exit "Img conversion failed\n"
	fi
	unset check_err
	fi

	$lyellow; echo "Mapping image with qemu..."; $normal
	if [ ! $nbd1_mapped == 1 ]; then
		if ! qemu_map "nbd1" "$outfile"; then
			err_exit "Error during image mapping\n"
		fi
	fi

	$yellow; echo "Mounting Partitions..."; $normal

	if ! mount_part "/dev/nbd1p2" "esd" &&
		 ! mount_part "/dev/nbd1p3" "esd"; then
			err_exit "Cannot mount esd\n"
	fi

	if [ -f "/mnt/osx/esd/BaseSystem.dmg" ]; then
		outfile="${filepath}/BaseSystem.img"
		if [ ! -e "$outfile" ]; then
			echo "Converting BaseSystem.dmg..."
			$dmg2img "/mnt/osx/esd/BaseSystem.dmg" "$outfile"
			if [ ! $? == 0 ] || [ ! -f "$outfile" ]; then
				err_exit "Img conversion failed\n"
			fi
		fi

		echo "Mapping BaseSystem with qemu..."
		if [ ! $nbd2_mapped == 1 ]; then
			if ! qemu_map "nbd2" "$outfile"; then
				err_exit "Error during BaseSystem mapping\n"
			fi
		fi

		if ! mount_part "/dev/nbd2p2" "base"; then
			err_exit "Cannot mount BaseSystem\n"
		fi
	fi
	detect_osx_version

	do_system
	do_kernel "esd"

	if [ ! "$patchmbr" == "false" ]; then
		docheck_mbr
	fi
	sync

	do_finalize

	sync
	cleanup
	$lgreen; echo "All Done!"; $normal
	if [ $virtualdev == 1 ] && [ "$dextension" == ".img" ] || [ "$dextension" == ".hdd" ]; then
		read -p "Do you want to convert virtual image to a VDI file? (y/n)" -n1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]];then
			vboxmanage convertdd  "$dev" ""$devpath/$dfilename".vdi"
			if [ ! $? == 0 ] || [ ! -f ""$devpath/$dfilename".vdi" ]; then
				err_exit "Conversion Failed\n"
			else
				chmod 666 "$devpath/$dfilename".vdi
				chown "$SUDO_USER":"$SUDO_USER" "$devpath/$dfilename".vdi
				read -p "Do you want to delete the img file? (y/n)" -n1 -r
				echo
				if [[ $REPLY =~ ^[Yy]$ ]];then
					rm "$dev"
				fi
			fi
		fi
	fi
	exit 0
}

main "$@"
