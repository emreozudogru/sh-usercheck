#!/bin/bash
#
# Written by Emre Ozudogru

# Detect RHEL version last log date position
source /etc/os-release
  case "$VERSION_ID" in
    7*)
      echo RHEL7 Detected $rhel_version
      last_login_position=44  # Position in RHEL 7
      ;;
    8*|9*)
      echo RHEL89 Detected $rhel_version
      last_login_position=69  # Position in RHEL 8 and 9
      ;;
    *)
      echo "Unsupported RHEL version: $rhel_version. Using default position."
      last_login_position=44  # Use default for unknown versions
      ;;
  esac

pause
# Get all users from /etc/passwd and lastlog
users_passwd=$(cut -d: -f1 /etc/passwd)
users_lastlog=$( lastlog | awk '{print $1}' | tail -n +2 )
users=$(for R in "${users_passwd[@]}" "${users_lastlog[@]}" ; do echo "$R" ; done | sort -du)
echo "Username;Status;Sudo-Rights;Last-Login"

for user in $users; do
  # Check for presence of "nologin" in the shell field
  shell=$(grep -E "^$user:.*nologin$" /etc/passwd)

  # Determine user status based on shell field and passwd -S output
  if [[ -n "$shell" ]]; then
    status="Disabled-nologin"
  else
    # Use `passwd -S` for compatibility and security (avoid sensitive shadow file details)
    status=$(passwd -S $user | awk '{print $2}')

    # Handle usrer statuses accurately
    case "$status" in
      LK) status="Disabled-locked" ;;
      PS) status="Enabled" ;;
      user.) status="IPA-User"
        ipa-disabled=$(ipa user-status pquezada 2>/dev/null | awk 'NR==2 {print $3}')
        case "$ipa-disabled"
          True) status="IPA-Disabled";;
          False) status="IPA-Enabled";;
        esac
      ;;
      *)  status="$status"          ;;
    esac
  fi

  # Check for sudo rights using a secure method (avoids revealing full command)
  sudo_rights="No"
  if sudo -l -U $user 2>/dev/null | grep -q "(ALL)"; then
    sudo_rights="Yes"
  fi

  # Get last login date
  last_login=$(lastlog -u $user 2>/dev/null | awk -v pos="$last_login_position" '{print substr($0,pos,30)}' | tail -n 1 || echo "N/A")
  echo "$user;$status;$sudo_rights;$last_login"
done

