#!/bin/bash
#
# Written by Emre Ozudogru

# Detect RHEL version
detect_rhel_version() {
  release_file="/etc/os-release"  # Use /etc/os-release for accuracy and compatibility

  rhel_version=$(grep -i -w "VERSION_ID" "$release_file" | cut -d "=" -f 2 | tr -d '"')

  if [[ -z "$rhel_version" ]]; then
    echo "Unable to determine RHEL version. Defaulting to RHEL 7 logic."
    rhel_version="7"  # Assume RHEL 7 if unable to detect
  fi

  echo "Detected RHEL version $rhel_version."
}

# Determine last login position based on RHEL version
get_last_login_position() {
  case "$rhel_version" in
    7)
      last_login_position=44  # Position in RHEL 7
      ;;
    8|9)
      last_login_position=69  # Position in RHEL 8 and 9
      ;;
    *)
      echo "Unsupported RHEL version: $rhel_version. Using default position."
      last_login_position=44  # Use default for unknown versions
      ;;
  esac
}


# Get all users
users_passwd=$(cut -d: -f1 /etc/passwd)
users_lastlog=$( lastlog | awk '{print $1}')
users=$(for R in "${users_passwd[@]}" "${users_lastlog[@]}" ; do echo "$R" ; done | sort -du)


for user in $users; do
  # Check for presence of "nologin" in the shell field
  shell=$(grep -E "^$user:.*nologin$" /etc/passwd)


  # Determine user status based on shell field and passwd -S output
  if [[ -n "$shell" ]]; then
    status="Disabled-nologin"
  else
    # Use `passwd -S` for compatibility and security (avoid sensitive shadow file details)
    status=$(passwd -S $user | awk '{print $2}')

    # Handle locked (LK) and inactive (PS) statuses accurately
    case "$status" in
      LK) status="Disabled-locked" ;;
      PS) status="Enabled" ;;
      *)  status="$status"          ;;
    esac
  fi

  # Check for sudo rights using a secure method (avoids revealing full command)
  sudo_rights="No"
  if sudo -l -U $user 2>/dev/null | grep -q "(ALL)"; then
    sudo_rights="Yes"
  fi

  # Get last login date (consider error handling and unavailable information)
  last_login=$(lastlog -u $user 2>/dev/null | awk -v pos="$last_login_position" '{print substr($0,pos,30)}' | tail -n 1 || echo "N/A")

  echo "$user;$status;$sudo_rights;$last_login"
done

