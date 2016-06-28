#!/bin/bash

#Automatically downloads new versions of Tron script
#This script is designed to update mirrors for Tron script. You should probably run it as a cron job.
#I have mine setup to run ever 10 minutes to make sure the mirror is as up-to-date
#as possible without hammering on the main mirror too much

#Tron script is located at http://reddit.com/r/Tronscript

#Written by reddit.com/u/-jimmyrustles
#Modified by reddit.com/u/danodemano (see changelog)
#VERSION 8.0

#CHANGELOG:
#V1.0 Initial release
#V1.1 Forgot double quotes around some variables.
#V2.0 Added file integrity check.
#V3.0 Use HTTPS for updating instead of HTTP. Option to purge old versions when updating. Simplified and fixed several things. Added more comments and changed appearance.
#V3.5 Added option to symlink updated file. Fixed "find" searching subdirectories when deleting.
#V3.6 Do not use absolute symbolic links.
#V3.7 Fix symlink getting deleted when updating
#*************************************************Adopted by Danodemano*************************************************
#V3.8 Added updating of sha256sum file in addition to md5sum file, added option for maximum download attempts, added warning for where to stop editing, general code cleanup
#V3.9 Fixed boolean operators to be true boolean instead of string true/false, added delay before re-attempting failed download
#V4.0 Fixed the old file removal to work correctly and added variable for delay time before re-download
#V4.1 Re-worked logic at end and removed unneeded statements
#V4.2 Updated mirror address
#V5.0 Updated to use sha256 sum file
#v5.5 Verify signature file of the sha256sum, added email alerting on failure, removed md5sum
#v5.6 Added email alerting on update of mirror
#v5.7 Added email error handling and changed if statement for consistency
#v6.0 Added in optional logging of nearly all outputs and cleanup/update comments
#v6.1 Fixed bug to not check GPG key if sha256sum file not updated or not found, fixed bug in download retry logic
#v6.2 Added option to download to temp directory them move to the actual repo directory, removed command line download dir option
#v6.3 Fixed bug with line breaks in sha256sum file, fixed coloring bug
#v7.0 Overhaul of update check logic to also compare the SHA256 sums in addition to the version number
#v7.5 Moved configurations to dedicated ini file so that updates don't require a reconfiguration
#v8.0 Changed update logic to keep extending check time on failure, script also dies if another copy is already executing

#TODO
# - Nothing -

#USAGE:
#Run this as a cron job at regular intervals - I run mine ever 10 minutes something like this:
#10,20,30,40,50 * * * * apache	/var/www/scripts/tronupdate.sh  > /dev/null 2>&1
#NOTE: Pick your own minutes to run the script to minimize load on the official repo

#The MIT License (MIT)

#Copyright (c) 2015 Daniel Bunyard

#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

#*************************************************************************************************************************************
#*************************************************************************************************************************************
#*************************************************************************************************************************************
# CONFIGURATION IS NOW DONE IN DEDICATED tronupdate.ini FILE - PLEASE MAKE ANY NEEDED CHANGES THERE
#*************************************************************************************************************************************
#*************************************************************************************************************************************
#*************************************************************************************************************************************

#*************************************************************************************************************************************
#*************************************************************************************************************************************
#*************************************************************************************************************************************
# WARNING WARNING WARNING - UNLESS YOU KNOW WHAT YOU ARE DOING DO NOT EDIT BELOW THIS LINE - WARNING WARNING WARNING
#*************************************************************************************************************************************
#*************************************************************************************************************************************
#*************************************************************************************************************************************

#Begin script
#**********

#Get this scripts name so we can check if already running
my_name=$(basename -- "$0")

#Before doing anything make sure another copy isn't already running, exit if so
if [ $(pidof -x "$my_name"| wc -w) -gt 2 ]; then
	echo "A copy of this script is already running - exiting!"
	exit
fi #end if [ $(pidof -x "$my_name"| wc -w) -gt 2 ]; then

#Text colors for use in console messages - probably don't want to mess with this
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)
reset=$(tput sgr0)
invert=$(tput rev)
#End text colors

#Change to the current running directory
cd "${BASH_SOURCE%/*}"

#Verify that the config file exists
if [ ! -f tronupdate.ini ]; then
    echo "Configuration file not found - exiting!"
	exit
fi #end if [ ! -f tronupdate.ini ]; then

#We need to get all the configurations from the ini file
downloaddir=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /download_directory/) print $2}' tronupdate.ini | tr -d ' '`
purgeoldversions=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /purge_old_versions/) print $2}' tronupdate.ini | tr -d ' '`
symlink=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /symlink/) print $2}' tronupdate.ini | tr -d ' '`
maxdownloadattempts=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /max_download_attempts/) print $2}' tronupdate.ini | tr -d ' '`
sleeptime=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /sleep_time/) print $2}' tronupdate.ini | tr -d ' '`
checkgpg=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /check_gpg/) print $2}' tronupdate.ini | tr -d ' '`
sendemail=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /send_email/) print $2}' tronupdate.ini | tr -d ' '`
updateemail=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /update_email/) print $2}' tronupdate.ini | tr -d ' '`
emailfrom=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /email_from/) print $2}' tronupdate.ini | tr -d ' '`
emailto=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /email_to/) print $2}' tronupdate.ini | tr -d ' '`
enablelogging=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /enable_logging/) print $2}' tronupdate.ini | tr -d ' '`
overwritelog=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /overwrite_log/) print $2}' tronupdate.ini | tr -d ' '`
loglocation=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /log_location/) print $2}' tronupdate.ini | tr -d ' '`
downloadtemp=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /download_temp/) print $2}' tronupdate.ini | tr -d ' '`
tempdir=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /temp_dir/) print $2}' tronupdate.ini | tr -d ' '`
repodir=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /repo_dir/) print $2}' tronupdate.ini | tr -d ' '`
sha256sumasc=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /sha256sumasc/) print $2}' tronupdate.ini | tr -d ' '`
sha256sumsurl=`awk -F '=' '{if (! ($0 ~ /^;/) && $0 ~ /sha256sumsurl/) print $2}' tronupdate.ini | tr -d ' '`
#End parsing of configuration file

#For the moment we are going to override the download attempts variable.
#Need to make make a note to either remove it from the config or just depreciate it.
#We actually WANT the script to keep trying just on a longer and longer interval
#and not to launch another copy of itself which is handled above.
#This helps mitigate load to the main repo if a corrupted exe gets uploaded.
maxdownloadattempts=9999999

#Begin functions
#************

#Logging function
function logging {
	#Get the passed message and type
	message="$1"
	errortype="$2"

	#Only write the log if it's enabled
	if [ "$enablelogging" = true ]
	then
		#Write the message to the log file along with the date/time stamp then a line break
		echo "`date '+%Y%m%d %T.%N'` - $errortype: $message" | tr '\n' ' ' >> "${loglocation}" 2>&1
		echo >> "${loglocation}" 2>&1
	fi #end if [ "$enablelogging" == true ]
	
	#Echo out the message and a line break
	echo "$message"
	echo
} #end function logging {

#The email alert function that is used on error
function emailalert {
	#To keep the main code clean we will check it enabed here
	if [ "$sendemail" = true ]
	then
		#Get the needed variables passed to this function
		type="$1"
		passedsubject="$2"
		details="$3"
		
		#Get the hostname of this server and current time
		THISHOST=$(hostname)
		THISDATE=$(date)
		
		#Change up the message based on the type
		if [ "$type" = "error" ]
		then
			#Build the email message for an error
			subject="Tron Update Error - $passedsubject"
			body="There was an error with the Tron auto-update script on $THISHOST"
			body+=$'\n'
			body+="It is advised that you check on this at once!  Error details:"
			body+=$'\n'
			body+="$details"
			body+=$'\n\n'
			body+="Timestamp of alert: $THISDATE"
		elif [ "$type" = "update" ]
		then
			#Build the email message and update
			subject="Tron Mirror Updated!"
			body="The Tron mirror on $THISHOST was updated to version $latestversion!"
			body+=$'\n\n'
			body+="Timestamp of message: $THISDATE"
		else
			#We have a problem
			logging "Error sending email - no type specified!" "ERROR"
		fi #end if [ "$type" == "error" ]
		
		#Send the email message
		echo "$body" | mail -s "$subject" -r "$emailfrom" "$emailto"
	fi #end if [ "$sendemail" == true ]
} #end function emailalert {

#hash verify function
function verify {
	#Verify downloaded file using "sha256sum"
	echo "${green}"
	logging "VERIFYING DOWNLOADED FILE!" "INFO"
	echo "${reset}"
	
	#Get "correct" hash from sha256sums.txt
	hashline=$(tail -n 1 "$downloaddir/sha256sums.txt" | awk '{ print $1 }')
	logging "$hashline" "INFO"
	arrIN=(${hashline//,/ })
	correcthash=${arrIN[1]}
	
	#Get hash of downloaded file
	if [ "$downloadtemp" = true ]
	then 
		localhash=$(sha256sum "$tempdir/$updatefile" | awk '{ print $1 }')
	else
		localhash=$(sha256sum "$downloaddir/$updatefile" | awk '{ print $1 }')
	fi #end if [ "$downloadtemp" = true ]
	logging "$localhash" "INFO"
	
	#Print hashes 
	echo "${green}"
	logging "The hash should be: $correcthash" "INFO"
	logging "Your hash is: $localhash" "INFO"
	echo "${reset}"

	#Check if hashes match.
	if [ "$correcthash" = "$localhash" ]
	then
		echo "${green}"
		logging "Hash verified!" "INFO"
		echo "${reset}"
		verified=true
	else
		echo "${red}"
		logging "Invalid Hash!" "WARNING"
		echo "${reset}"
		verified=false
	fi #end if [ "$correcthash" == "$localhash" ]
} #end function verify {

#GPG key verify function
function verifygpg {
	#Verify that the GPG signing for the sha256sum file is correct
	echo "${green}"
	logging "VERIFYING GPG OF SHA256 FILE!" "INFO"
	echo "${reset}"
	gpg --verify "$downloaddir/sha256sums.txt.asc" "$downloaddir/sha256sums.txt"
	
	#Check if we have a valid signature
	if [ $? -eq 0 ]
	then
		#Signature valid
		echo "${green}"
		logging "GPG signature verified!" "INFO"
		echo "${reset}"
		gpgverified=true
	else
		#Signature invalid
		echo "${red}"
		logging "Invalid GPG Signature!" "ERROR"
		echo "${reset}"
		gpgverified=false
	fi #end if [ $? -eq 0 ]
} #end function verifygpg {

#function that redownloads if not verified, quits if verified
function checkifverified {
	if [ "$verified" = true ]
	then
		echo "${green}"
		logging "Hashes Match! $updatefile Verified!" "INFO"
		logging "MIRROR UPDATED!" "INFO"
		echo "${reset}"
		
		#Move the file if we are downloading to temp
		if [ "$downloadtemp" = true ]
		then
			echo "${green}"
			logging "Moving file from $tempdir to $downloaddir." "INFO"
			echo "${reset}"
			mv "$tempdir/$updatefile" "$downloaddir/$updatefile"
		fi #end if [ "$downloadtemp" = true ]
		
		#Purge old versions (if enabled)
		if [ "$purgeoldversions" = true ]
		then
			echo "${red}"
			logging "Removing old Tron versions!" "INFO"
			echo "${reset}"
			echo "${blue}"
			#Produce list of old Tron files, and use xargs to parse and delete these files.
			find "$downloaddir" -maxdepth 1 -name 'Tron*.exe' | grep -v "$updatefile" | xargs -n 3 | sed 's/.*/"&"/' | xargs rm -f -v
			echo "${reset}"
			echo "${green}"
			logging "Done removing old versions!" "INFO"
			echo "${reset}"
		fi #end if [ "$purgeoldversions" == true ]
	
		#symlink updated Tron file to "latest.exe" (if enabled)	
		if [ "$symlink" == true ]
		then
			echo "${blue}"
			logging "symlinking to \"latest.exe\"" "INFO"
			echo "${reset}"
			#change dir to download dir.
			cd "$downloaddir"
			#symlink. -s (symbolic) -f (force) -v (verbose)
			output1=`ln -s -f -v "$updatefile" "latest.exe"`
			logging "$output1" "INFO"
			echo "${green}"
			logging "Done creating symlink"
			echo "!${reset}"
		fi #end if [ "$symlink" == true ]
		
		#Email out an alert if enabled
		if [ "$updateemail" = true ]
		then
			emailalert "update"
		fi #end if [ "$updateemail" == true ]
		
		#All done - exit the script
		exit
	else
		#As the download fails we keep increasing the sleeptime to avoid repeated hammering on the main mirror
		#in the event a corrupted EXE gets uploaded.  We are just going to double the sleeptime each loop
		#hopefully creating less and less load until checks are few and far between.  We are also going to set an 
		#upper limit of ~2 hours so things don't get WAY out of control.
		if [ "$sleeptime" <= 7200 ]
		then
			sleeptime=$((sleeptime * 2))
		fi #end if [ "$sleeptime" <= 7200 ]
	
		echo "${red}"
		logging "Hashes do not match! $updatefile does not match repo file! Will retry in $sleeptime seconds!" "WARNING"
		echo "${reset}"
		
		#From either the temp dir or the actual dir
		if [ "$downloadtemp" = true ]
		then
			rm -f -v "$tempdir/$updatefile"
			#Sleep based on the variable above in the configs
			sleep $sleeptime
			#Retry the download
			output1=`wget -nc -O "${tempdir}"/"${updatefile}" "${repodir}"/"${updatefile}"`
		else
			rm -f -v "$downloaddir/$updatefile"
			#Sleep based on the variable above in the configs
			sleep $sleeptime
			#Retry the download
			output1=`wget -nc -O "${downloaddir}"/"${updatefile}" "${repodir}"/"${updatefile}"`
		fi #end if [ "$downloadtemp" = true ]
		
		echo "${invert}"
		logging "$output1" "INFO"
		echo "${reset}"
		
		#increment "downloadtries" by 1 to keep tabs on the attempts
		downloadtries=$((downloadtries + 1))
	fi #end if [ "$verified" == true ]
} #end function checkifverified {

#End functions
#***********

#Begin main code
#**************

#If we are set to overwrite the log remove the log file
if [ "$overwritelog" = true ]
then
	#Remove the current log file
	rm -f -v "$loglocation"
fi #end if [ "$overwritelog" == true ]

#Before we get the updated sha256sum file lets get the current hash from the local file
IN=$(tail -n 1 "$downloaddir/sha256sums.txt")
arrIN=(${IN//,/ })
localversionhash=${arrIN[1]}
echo "${green}"
logging "Local hash is: $localversionhash" "INFO"
echo "${reset}"

#download sha256sums.txt.asc to $downloaddir if repo version is newer
output1=`wget -P "${downloaddir}" -N "${sha256sumasc}" 2>&1`
#wget -P "$downloaddir" -N "$sha256sumasc" >> output
echo "${invert}"
logging "$output1" "INFO"
echo "${reset}"

#download sha256sum.txt to $downloaddir if repo version is newer
output1=`wget -P "${downloaddir}" -N "${sha256sumsurl}" 2>&1`
echo "${invert}"
logging "$output1" "INFO"
echo "${reset}"

#First we need to check and see if we downloaded a new sha256sum file
#and also make sure that the remote file exists
if [[ $output1 = *"Server file no newer than local file"* ]]
then
	#File not updated
	echo "${green}"
	logging "SHA256SUM file was no newer - not checking GPG key" "INFO"
	echo "${reset}"
elif [[ $output1 = *"ERROR 404"* ]]
then
	#File not found
	echo "${green}"
	logging "SHA256SUM file was not found - not checking GPG key" "WARNING"
	echo "${reset}"
else
	#If enabled verify the gpg signature of the downloaded sha256sum
	#We end here if it cannot be verified!
	if [ "$checkgpg" = true ]
	then
		verifygpg
		if [ "$gpgverified" = false ]
		then
			#Invalid GPG key, we exit the script here
			echo "${red}"
			logging "Unable to verify the GPG signature.  Script will now exit!" "ERROR"
			echo "${reset}"
			#Send an email alert about the bag signature
			emailalert "error" "Invalid GPG" "Unable to verify the GPG signature of the sha256sum file.  This could mean a corrupt file, bad download, or missing file."
			exit
		else
			#GPG key is good, continue
			echo "${green}"
			logging "GPG key verified - script will now continue!" "INFO"
			echo "${reset}"
		fi #end if [ "$gpgverified" == false ]
	fi #end if [ "$checkgpg" == true ]
fi #end if [[ $output1 == *"Server file no newer than local file"* ]]

#Get latest version number
latestversion=$(tail -n 1 "$downloaddir/sha256sums.txt" | awk '{ print $2 }')
echo "${green}"
logging "Latest version is: $latestversion" "INFO"
echo "${reset}"

#Get the latest version hash
IN=$(tail -n 1 "$downloaddir/sha256sums.txt")
arrIN=(${IN//,/ })
latestversionhash=${arrIN[1]}
echo "${green}"
logging "Local hash is: $latestversionhash" "INFO"
echo "${reset}"

#Get the local version number
localversion=$(ls -1 "$downloaddir" | grep 'Tron' | grep 'exe' | tail -n 1 | awk '{ print $2 }')
echo "${green}"
logging "Local version: $localversion" "INFO"
echo "${reset}"

#compare local and remote versions - update as needed
if [ "$latestversion" != "$localversion" ] || [ "$latestversionhash" != "$localversionhash" ]
then
	logging "MIRROR IS OUT OF DATE! UPDATING!" "INFO"
	#identify version to update to
	line=$(tail -n 1 "$downloaddir/sha256sums.txt")
	arrIN=(${line//,/ })
	name=${arrIN[2]}
	version=${arrIN[3]}
	date=${arrIN[4]}
	updatefile="$name $version $date"
	#Remove linebreaks from the updatefile
	updatefile=$(echo $updatefile | sed -e 's/\r//g')
	logging "File to download is: $updatefile" "INFO"
	#Check if we are downloading to a temp directory then download the file
	if [ "$downloadtemp" = true ]
	then
		#Create the directory if it doesn't exist
		if [ ! -d "$DIRECTORY" ]; then
			mkdir "$tempdir"
		fi #end if [ ! -d "$DIRECTORY" ]; then
		output1=`wget -nc -O "${tempdir}"/"${updatefile}" "${repodir}"/"${updatefile}"`
	else
		output1=`wget -nc -O "${downloaddir}"/"${updatefile}" "${repodir}"/"${updatefile}"`
	fi #end if [ "$downloadtemp" = true ]
	echo "${invert}"
	logging "$output1" "INFO"
	echo "${reset}"
	#set download tries to "1"
	downloadtries=1
	
	#Run while file is not verified
	while [ "$verified" != true ]
	do
		#do while download attempts is less than maxdownloadattempts variable
		if [ "$downloadtries" \< "$maxdownloadattempts" ]
		then
			#Try to download/verify the file
			verify
			checkifverified
		else
			#fail if still can't verify after $maxdownloadattempts downloads
			echo "${red}"
			logging "After $downloadtries downloads $updatefile could still not be verified! Giving Up!" "ERROR"
			echo "${reset}"
			#Send an email about the failed download
			emailalert "error" "Update Failed" "After $downloadtries downloads $updatefile could still not be verified!"
			#cleanup corrupt file
			if [ "$downloadtemp" = true ]
			then
				rm -f -v "$tempdir/$updatefile"
			else
				rm -f -v "$downloaddir/$updatefile"
			fi #end if [ "$downloadtemp" = true ]
			#We are at the end - exit from the script
			exit
		fi #end if (( downloadtries < maxdownloadattempts ))
	done #end while [ "$verified" != true ]
else
	#Nothing to do - mirror is up-to-date
	logging "MIRROR IS UP TO DATE!" "INFO"
	exit
fi #end if [ "$latestversion" != "$localversion" ]

#End main code
#************

#End script
#********
