#!/bin/bash
# This script detects all access rights for this server and prints them in a CSV format.
# It also enables and disables user enumeration in /etc/sssd/sssd.conf temporarily.
# Written by Emre Ozudogru

# Print introduction for this script
cat << EOF
This script detects all access rights for this server. While it is running, it can affect the performance. Please use this script at non-peak hours.
If this server is ipa joined, please use 'kinit' before starting to get your kerberos ticket.
If you use this script for the first time, please add #enumerate = true after [domain/nyc.int.boldyn.net] line.
EOF
# Wait for user input to continue
read -p "Press enter to continue"
echo

# Detect RHEL version and last login date position
source /etc/os-release
case "$VERSION_ID" in
  7*) # RHEL 7
    echo "RHEL 7 detected. Exact Version is $VERSION_ID"
    last_login_position=44
    ;;
  8*|9*) # RHEL 8 or 9
    echo "RHEL 8 or 9 detected. Exact Version is $VERSION_ID"
    last_login_position=69
    ;;
  *) # Unsupported RHEL version
    echo "Unsupported RHEL version: $VERSION_ID. Using default position."
    last_login_position=44
    ;;
esac

# Enable user enumeration by uncommenting the line in /etc/sssd/sssd.conf
# Make a backup of the original file
sed -i 's/#enumerate = true/enumerate = true/' /etc/sssd/sssd.conf
# Restart the sssd service to apply the changes
service sssd restart
sleep 5

# Get all users from /etc/passwd and lastlog and sort them uniquely
#users=$(comm -12 <(cut -d: -f1 /etc/passwd | sort) <(lastlog | awk '{print $1}' | tail -n +2 | sort))
users=$(cat <(cut -d: -f1 /etc/passwd) <(lastlog | awk '{print $1}' | tail -n +2) | sort -u)

echo
echo "Username,Status,Sudo-Rights,Last-Login"

# Loop through each user and get their status, sudo rights, and last login date
for user in $users; do
  # Check if the user has nologin as their shell
  if grep -qE "^$user:.*nologin$" /etc/passwd; then
    status="Disabled-nologin"
  else
    # Use passwd -S for compatibility and security
    status=$(passwd -S $user | awk '{print $2}')
    # Handle different user statuses
    case "$status" in
      LK) status="Disabled-locked" ;;
      PS) status="Enabled" ;;
      user.) # IPA user
        status="IPA-User"
        # Check if the IPA user is disabled
        if ipa user-status $user 2>/dev/null | awk 'NR==2 {print $3}' | grep -q True; then
          status="IPA-Disabled"
        else
          status="IPA-Enabled"
        fi
        ;;
      *)  status="$status" ;;
    esac
  fi

  # Check if the user has sudo rights by using sudo -l -U
  sudo_rights="No"
  if sudo -l -U $user 2>/dev/null | grep -q "(ALL)"; then
    sudo_rights="Yes"
  fi

  # Get the last login date by using lastlog -u and awk
  last_login=$(lastlog -u $user 2>/dev/null | awk -v pos="$last_login_position" '{print substr($0,pos,30)}' | tail -n 1 || echo "N/A")
  # Print the user information in CSV format
  echo "$user,$status,$sudo_rights,$last_login"
done

# Disable user enumeration by commenting the line in /etc/sssd/sssd.conf
sed -i 's/enumerate = true/#enumerate = true/' /etc/sssd/sssd.conf

# Restart the sssd service to apply the changes
service sssd restart
sleep 1