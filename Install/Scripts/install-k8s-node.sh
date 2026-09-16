#!/usr/bin/env bash
#------------------

#-------------------------------------------------------------
# Script Description
#-------------------------------------------------------------

################################################################################
# This script bootstraps an existing single node as a Kubernetes node. It can
# be used to install and configure Kubernetes on that node as either a master
# node or a worker node. This script assumes the underlying infrastructure is
# already built and the node is up and running with a supported OS installed.
#
# To use this script, run it once on each node in your Kubernetes cluster,
# one node at a time - starting with the nodes you have considered to be Master
# node(s).
#
# This script will prompt the user with several questions and gather the
# information needed to install and configure the node for a Kubernetes
# cluster properly.
#
# This script is intended to speed up the creation of a Kubernetes cluster in
# a demo environment. Do not use in a production environment.
#
# The installation performed by this script is based on the official
# Kubernetes installation guide, using the kubeadm installation method.
################################################################################

#=========================================================================================

#-------------------------------------------------------------
# Strict bash safety + error/interrupt traps
#-------------------------------------------------------------

# -E: ERR trap inherits into functions/subshells | -e: exit on any failed command
# -u: unset variables are errors | -o pipefail: pipeline fails if any stage fails
set -Eeuo pipefail

# Catch Ctrl+C / kill signals and exit with a clean message instead of dying silently
trap 'echo -e "\n ---- Script interrupted. Exiting..."; exit 1' INT TERM

# Catch any failure triggered by set -e and print the line + command that caused it
trap 'rc=$?; echo -e "\n ---- ERROR: line ${LINENO}: ${BASH_COMMAND}" >&2; exit $rc' ERR

#=========================================================================================

#-------------------------------------------------------------
# Set Colors For Outputs
#-------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GREY='\033[0;90m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[1;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'   # Reset / No Color

#=========================================================================================

# Reset variables (script + GOVC env) for safe re-runs
#-------------------------------------------------------------

#Unset All Variables Used In This Script

#=========================================================================================

#-------------------------------------------------------------
# Functions To Be Used In Script
#-------------------------------------------------------------

# Function to Confirm user input Y/N
confirm_yn() {
  local prompt="$1" ans
  while true; do
    read -rp "$prompt" ans
    case "$ans" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo -e "${RED}   Invalid input. Please enter Y or N only.${NC}" >&2 ;;
    esac
  done
}

# Function to validate an IPv4 address using regex and range check
validate_ip() {
  local ip="$1"
  local regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'

  # --- Check the value matches the basic dotted-decimal pattern ---
  if [[ ! "$ip" =~ $regex ]]; then
    return 1
  fi

  # --- Check each octet is within 0-255 ---
  for octet in "${BASH_REMATCH[@]:1}"; do
    if (( octet > 255 )); then
      return 1
    fi
  done

  return 0
}

# Function to validate the shape of a kubeadm join command for a CONTROL-PLANE node
validate_join_command_master() {
  local cmd="$1"

  # --- Must start with kubeadm join followed by an IP:PORT ---
  [[ "$cmd" =~ ^kubeadm\ join\ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+ ]] || return 1

  # --- Must contain a --token value ---
  [[ "$cmd" =~ --token\ [A-Za-z0-9.]+ ]] || return 1

  # --- Must contain a --discovery-token-ca-cert-hash sha256 value (64 hex chars) ---
  [[ "$cmd" =~ --discovery-token-ca-cert-hash\ sha256:[A-Fa-f0-9]{64} ]] || return 1

  # --- Must contain --control-plane and a --certificate-key value (64 hex chars) ---
  [[ "$cmd" =~ --control-plane ]] || return 1
  [[ "$cmd" =~ --certificate-key\ [A-Fa-f0-9]{64} ]] || return 1

  return 0
}

# Function to validate the shape of a kubeadm join command for a WORKER node
validate_join_command_worker() {
  local cmd="$1"

  # --- Must start with kubeadm join followed by an IP:PORT ---
  [[ "$cmd" =~ ^kubeadm\ join\ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+ ]] || return 1

  # --- Must contain a --token value ---
  [[ "$cmd" =~ --token\ [A-Za-z0-9.]+ ]] || return 1

  # --- Must contain a --discovery-token-ca-cert-hash sha256 value (64 hex chars) ---
  [[ "$cmd" =~ --discovery-token-ca-cert-hash\ sha256:[A-Fa-f0-9]{64} ]] || return 1

  return 0
}

# Function to validate a CIDR (e.g. 10.244.0.0/16) using regex and range checks
validate_cidr() {
  local cidr="$1"
  local regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$'

  # --- Check the value matches the CIDR pattern ---
  if [[ ! "$cidr" =~ $regex ]]; then
    return 1
  fi

  # --- Check each octet is within 0-255 ---
  for octet in "${BASH_REMATCH[@]:1:4}"; do
    if (( octet > 255 )); then
      return 1
    fi
  done

  # --- Check the prefix is within 0-32 ---
  local prefix="${BASH_REMATCH[5]}"
  if (( prefix > 32 )); then
    return 1
  fi

  return 0
}

#=========================================================================================

#-------------------------------------------------------------
# Check User To Be Root - Exit If Not
#-------------------------------------------------------------

# Check EUID and if not equal zero (not root) exit with failure
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo -e "${RED} ------------------------------------------------  "
    echo -e "${RED} ---- ERROR: This script must be run as root. ${NC}"
    echo -e "${RED} ------------------------------------------------  "
    echo ""
    exit 1
fi

#=========================================================================================

#-------------------------------------------------------------
# Create bannar & Print Starting Script Message
#-------------------------------------------------------------

echo -e "${GREEN}"
echo "  ---------------------------------------------------------------------  "
echo " | =================================================================== | "
echo " |                 Kubernetes Node Bootstrap (kubeadm)                 | "
echo " | ------------------------------------------------------------------- | "
echo " |                                                                     | "
echo " |   ██╗  ██╗ █████╗ ███████╗    ███╗   ██╗ ██████╗ ██████╗ ███████╗   | "
echo " |   ██║ ██╔╝██╔══██╗██╔════╝    ████╗  ██║██╔═══██╗██╔══██╗██╔════╝   | "
echo " |   █████╔╝ ╚█████╔╝███████╗    ██╔██╗ ██║██║   ██║██║  ██║█████╗     | "
echo " |   ██╔═██╗ ██╔══██╗╚════██║    ██║╚██╗██║██║   ██║██║  ██║██╔══╝     | "
echo " |   ██║  ██╗╚█████╔╝███████║    ██║ ╚████║╚██████╔╝██████╔╝███████╗   | "
echo " |   ╚═╝  ╚═╝ ╚════╝ ╚══════╝    ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝   | "
echo " |                                                                     | "
echo " |   ███████╗███████╗████████╗██╗   ██╗██████╗                         | "
echo " |   ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗                        | "
echo " |   ███████╗█████╗     ██║   ██║   ██║██████╔╝                        | "
echo " |   ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝                         | "
echo " |   ███████║███████╗   ██║   ╚██████╔╝██║                             | "
echo " |   ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝                             | "
echo " |                                                                     | "
echo "  ---------------------------------------------------------------------  "
echo ""
echo " --- Starting the Kubernetes node bootstrap script (kubeadm)..."
echo -e "${NC}"

echo " ================================================================================== "
echo ""

#=========================================================================================

#-------------------------------------------------------------
# Collect and Confirm User Inputs 
#-------------------------------------------------------------

echo -e "${GREEN} Part 1: - Collect Required Info From User:${NC}"
echo -e "${GREEN} ------------------------------------------${NC}"

# Ask for the number of master nodes in this cluster, perform a sanity check, and then confirm with the user
while true; do
  # --- Print message ---
  echo ""
  echo -e "${YELLOW} - How many master nodes will this cluster have? - Choose from the options below:${NC}"
  echo -e "${YELLOW}   1) 1 master node${NC}"
  echo -e "${YELLOW}   2) 3 master nodes${NC}"

  # --- Ask for master node count ---
  while true; do
    read -rp "   Enter your choice (1 or 2): " MASTER_CHOICE
    [[ "$MASTER_CHOICE" =~ ^[12]$ ]] && break
    echo -e "${RED}   Invalid choice. Please enter 1 or 2.${NC}"
  done

  # --- Set variable based on choice ---
  if [[ "$MASTER_CHOICE" == "1" ]]; then
    echo -e "${CYAN}      Selected: 1 master node${NC}"
    MASTER_COUNT=1
  else
    echo -e "${CYAN}      Selected: 3 master nodes${NC}"
    MASTER_COUNT=3
  fi

  # --- Print summary + confirm ---
  echo "   Please confirm the master node count selection: Your selection is $MASTER_COUNT"
  if confirm_yn "   Is this correct? (Y/N): "; then
    echo -e "${CYAN}   Master node selection confirmed. Proceeding...${NC}"
    break
  else
    echo -e "${CYAN}   Re-entering master node selection...${NC}"
  fi
done

    #------------------------------------------------------------------------------

# Ask if this node will be a master node or a worker node, perform a sanity check, and then confirm with the user
while true; do
  # --- Print message ---
  echo ""
  echo -e "${YELLOW} - Will this node be a master node or a worker node? - Choose from the options below:${NC}"
  echo -e "${YELLOW}   1) Master node${NC}"
  echo -e "${YELLOW}   2) Worker node${NC}"

  # --- Ask for node role ---
  while true; do
    read -rp "   Enter your choice (1 or 2): " ROLE_CHOICE
    [[ "$ROLE_CHOICE" =~ ^[12]$ ]] && break
    echo -e "${RED}   Invalid choice. Please enter 1 or 2.${NC}"
  done

  # --- Set variable based on choice ---
  if [[ "$ROLE_CHOICE" == "1" ]]; then
    echo -e "${CYAN}      Selected: Master node${NC}"
    NODE_ROLE="master"
  else
    echo -e "${CYAN}      Selected: Worker node${NC}"
    NODE_ROLE="worker"
  fi

  # --- Print summary + confirm ---
  echo "   Please confirm the node role selection: Your selection is $NODE_ROLE"
  if confirm_yn "   Is this correct? (Y/N): "; then
    echo -e "${CYAN}   Node role selection confirmed. Proceeding...${NC}"
    break
  else
    echo -e "${CYAN}   Re-entering node role selection...${NC}"
  fi
done

    #------------------------------------------------------------------------------

# If this is a master node and there are 3 masters, ask if this is the first master or a master joining an existing one
if [[ "$NODE_ROLE" == "master" && "$MASTER_COUNT" == "3" ]]; then
  # --- Print context message based on previous selections ---
  echo ""
  echo -e "${YELLOW} - Based on your previous selections, this is a master node in a cluster with 3 master nodes in total.${NC}"
  
  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Is this the first master node, or will it join an existing master node? - Choose from the options below:${NC}"
    echo -e "${YELLOW}   1) First master node (initialize a new cluster)${NC}"
    echo -e "${YELLOW}   2) Joining master node (join an existing master node)${NC}"

    # --- Ask for first/joining master choice ---
    while true; do
      read -rp "   Enter your choice (1 or 2): " MASTER_ROLE_CHOICE
      [[ "$MASTER_ROLE_CHOICE" =~ ^[12]$ ]] && break
      echo -e "${RED}   Invalid choice. Please enter 1 or 2.${NC}"
    done

    # --- Set variable based on choice ---
    if [[ "$MASTER_ROLE_CHOICE" == "1" ]]; then
      echo -e "${CYAN}      Selected: First master node${NC}"
      IS_FIRST_MASTER="yes"
    else
      echo -e "${CYAN}      Selected: Joining master node${NC}"
      IS_FIRST_MASTER="no"
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the first/joining master selection: Your selection is $IS_FIRST_MASTER"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   First/joining master selection confirmed. Proceeding...${NC}"
      break
    else
      echo -e "${CYAN}   Re-entering first/joining master selection...${NC}"
    fi

    # Add a space for separation
    echo ""

  done
else
  # With only 1 master node, this node is always the first (and only) master
  if [[ "$NODE_ROLE" == "master" ]]; then
    IS_FIRST_MASTER="yes"
  fi
fi

    #------------------------------------------------------------------------------

# If this is the first master node in a 3-master cluster, ask for the Load Balancer IP 
# Note: this script will depend on IP only and not FQDN for simplicity
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "yes" && "$MASTER_COUNT" == "3" ]]; then
  # --- Print context message based on previous selections ---
  echo ""
  echo -e "${YELLOW} - Based on your previous selections, this is the first master node in a cluster with 3 master nodes in total - Load Balancer info is required..${NC}"

  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Please provide the Load Balancer IP serving the 3 master nodes:${NC}"

    # --- Read the LB endpoint value ---
    read -rp "   Enter IP: " ENDPOINT_INPUT

    # --- Sanity check: value must be a valid IPv4 address ---
    if ! validate_ip "$ENDPOINT_INPUT"; then
      echo -e "${RED}   Invalid input. Please enter a valid IP address.${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the Load Balancer IP: Your entry is $ENDPOINT_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Load Balancer IP confirmed. Proceeding...${NC}"
      MASTER_ENDPOINT="$ENDPOINT_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering Load Balancer IP...${NC}"
    fi
  done
fi

    #------------------------------------------------------------------------------

# If this is a master node that is joining another master node in a 3-master cluster, ask for the Load Balancer IP and the join command
# Note: this script will depend on IP only and not FQDN for simplicity
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "no" && "$MASTER_COUNT" == "3" ]]; then
  # --- Print context message based on previous selections ---
  echo ""
  echo -e "${YELLOW} - Based on your previous selections, this is a joining master node in a cluster with 3 master nodes in total - Load Balancer info and join command are required.${NC}"

  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Please provide the Load Balancer IP serving the 3 master nodes:${NC}"

    # --- Read the LB endpoint value ---
    read -rp "   Enter IP: " ENDPOINT_INPUT

    # --- Sanity check: value must be a valid IPv4 address ---
    if ! validate_ip "$ENDPOINT_INPUT"; then
      echo -e "${RED}   Invalid input. Please enter a valid IP address.${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the Load Balancer IP: Your entry is $ENDPOINT_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Load Balancer IP confirmed. Proceeding...${NC}"
      MASTER_ENDPOINT="$ENDPOINT_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering Load Balancer IP...${NC}"
    fi
  done

  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Please paste the full 'kubeadm join' command for a CONTROL-PLANE node (provided by the first master):${NC}"

    # --- Read the join command ---
    read -rp "   Join command: " JOIN_COMMAND_INPUT

    # --- Sanity check: value must match the expected control-plane join command format ---
    if ! validate_join_command_master "$JOIN_COMMAND_INPUT"; then
      echo -e "${RED}   Invalid input. This does not look like a valid control-plane 'kubeadm join' command.${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the join command: Your entry is $JOIN_COMMAND_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Join command confirmed. Proceeding...${NC}"
      JOIN_COMMAND="$JOIN_COMMAND_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering join command...${NC}"
    fi
  done
fi

    #------------------------------------------------------------------------------

# If this is the first master node, ask which CNI to install
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "yes" ]]; then
  # --- Print context message based on previous selections ---
  echo ""
  echo -e "${YELLOW} - Based on your previous selections, this is the first master node - CNI selection is required.${NC}"

  # Ask which CNI to install, perform a sanity check, and then confirm with the user
  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Which CNI should be installed on this cluster? - Choose from the options below:${NC}"
    echo -e "${YELLOW}   1) Calico${NC}"
    echo -e "${YELLOW}   2) Cilium${NC}"

    # --- Ask for CNI choice ---
    while true; do
      read -rp "   Enter your choice (1 or 2): " CNI_CHOICE_INPUT
      [[ "$CNI_CHOICE_INPUT" =~ ^[12]$ ]] && break
      echo -e "${RED}   Invalid choice. Please enter 1 or 2.${NC}"
    done

    # --- Set variable based on choice ---
    if [[ "$CNI_CHOICE_INPUT" == "1" ]]; then
      echo -e "${CYAN}      Selected: Calico${NC}"
      CNI_CHOICE="calico"
    else
      echo -e "${CYAN}      Selected: Cilium${NC}"
      CNI_CHOICE="cilium"
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the CNI selection: Your selection is $CNI_CHOICE"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   CNI selection confirmed. Proceeding...${NC}"
      break
    else
      echo -e "${CYAN}   Re-entering CNI selection...${NC}"
    fi
  done
fi

    #------------------------------------------------------------------------------

# If this is the first master node, ask for the Pod and Service CIDRs
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "yes" ]]; then
  # --- Print context message based on previous selections ---
  echo ""
  echo -e "${YELLOW} - Based on your previous selections, this is the first master node - network CIDR info is required.${NC}"
  echo -e "${RED}   Note: this script does not check for overlap between these CIDRs. The Pod CIDR, Service CIDR, and Node CIDR must NOT overlap with each other.${NC}"
  echo -e "${RED}   Note: an overlap will break the installation.${NC}"

  # --- Ask for the Pod (cluster) CIDR ---
  while true; do
    echo ""
    echo -e "${YELLOW} - Please provide the Pod (cluster) network CIDR (e.g. 10.244.0.0/16):${NC}"
    read -rp "   Enter CIDR: " POD_CIDR_INPUT

    # --- Sanity check: value must be a valid CIDR ---
    if ! validate_cidr "$POD_CIDR_INPUT"; then
      echo -e "${RED}   Invalid input. Please enter a valid CIDR (e.g. 10.244.0.0/16).${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the Pod CIDR: Your entry is $POD_CIDR_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Pod CIDR confirmed. Proceeding...${NC}"
      POD_CIDR="$POD_CIDR_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering Pod CIDR...${NC}"
    fi
  done

  # --- Ask for the Service CIDR ---
  while true; do
    echo ""
    echo -e "${YELLOW} - Please provide the Service network CIDR (e.g. 10.96.0.0/12):${NC}"
    read -rp "   Enter CIDR: " SVC_CIDR_INPUT

    # --- Sanity check: value must be a valid CIDR ---
    if ! validate_cidr "$SVC_CIDR_INPUT"; then
      echo -e "${RED}   Invalid input. Please enter a valid CIDR (e.g. 10.96.0.0/12).${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the Service CIDR: Your entry is $SVC_CIDR_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Service CIDR confirmed. Proceeding...${NC}"
      SVC_CIDR="$SVC_CIDR_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering Service CIDR...${NC}"
    fi
  done
fi

    #------------------------------------------------------------------------------

# If this is a worker node in a single-master cluster, ask for the master node IP and the join command
if [[ "$NODE_ROLE" == "worker" && "$MASTER_COUNT" == "1" ]]; then
  # --- Print context message based on previous selections ---
  echo ""
  echo -e "${YELLOW} - Based on your previous selections, this is a worker node in a single-master cluster - master node IP and join command are required.${NC}"

  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Please provide the master node IP (no load balancer in a single-master cluster):${NC}"

    # --- Read the master IP value ---
    read -rp "   Enter IP: " ENDPOINT_INPUT

    # --- Sanity check: value must be a valid IPv4 address ---
    if ! validate_ip "$ENDPOINT_INPUT"; then
      echo -e "${RED}   Invalid input. Please enter a valid IP address.${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the master node IP: Your entry is $ENDPOINT_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Master node IP confirmed. Proceeding...${NC}"
      MASTER_ENDPOINT="$ENDPOINT_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering master node IP...${NC}"
    fi
  done

  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Please paste the full 'kubeadm join' command for a WORKER node (provided by the first master):${NC}"

    # --- Read the join command ---
    read -rp "   Join command: " JOIN_COMMAND_INPUT

    # --- Sanity check: value must match the expected worker join command format ---
    if ! validate_join_command_worker "$JOIN_COMMAND_INPUT"; then
      echo -e "${RED}   Invalid input. This does not look like a valid worker 'kubeadm join' command.${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the join command: Your entry is $JOIN_COMMAND_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Join command confirmed. Proceeding...${NC}"
      JOIN_COMMAND="$JOIN_COMMAND_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering join command...${NC}"
    fi
  done
fi

    #------------------------------------------------------------------------------

# If this is a worker node in a 3-master cluster, ask for the Load Balancer IP and the join command
if [[ "$NODE_ROLE" == "worker" && "$MASTER_COUNT" == "3" ]]; then
  # --- Print context message based on previous selections ---
  echo ""
  echo -e "${YELLOW} - Based on your previous selections, this is a worker node in a cluster with 3 master nodes in total - Load Balancer info and join command are required.${NC}"

  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Please provide the Load Balancer IP serving the 3 master nodes:${NC}"

    # --- Read the LB endpoint value ---
    read -rp "   Enter IP: " ENDPOINT_INPUT

    # --- Sanity check: value must be a valid IPv4 address ---
    if ! validate_ip "$ENDPOINT_INPUT"; then
      echo -e "${RED}   Invalid input. Please enter a valid IP address.${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the Load Balancer IP: Your entry is $ENDPOINT_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Load Balancer IP confirmed. Proceeding...${NC}"
      MASTER_ENDPOINT="$ENDPOINT_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering Load Balancer IP...${NC}"
    fi
  done

  while true; do
    # --- Print message ---
    echo -e "${YELLOW} - Please paste the full 'kubeadm join' command for a WORKER node (provided by the first master):${NC}"

    # --- Read the join command ---
    read -rp "   Join command: " JOIN_COMMAND_INPUT

    # --- Sanity check: value must match the expected worker join command format ---
    if ! validate_join_command_worker "$JOIN_COMMAND_INPUT"; then
      echo -e "${RED}   Invalid input. This does not look like a valid worker 'kubeadm join' command.${NC}"
      continue
    fi

    # --- Print summary + confirm ---
    echo "   Please confirm the join command: Your entry is $JOIN_COMMAND_INPUT"
    if confirm_yn "   Is this correct? (Y/N): "; then
      echo -e "${CYAN}   Join command confirmed. Proceeding...${NC}"
      JOIN_COMMAND="$JOIN_COMMAND_INPUT"
      break
    else
      echo -e "${CYAN}   Re-entering join command...${NC}"
    fi
  done
fi

    #------------------------------------------------------------------------------

# Ask for the Kubernetes minor version to install, perform a sanity check, and then confirm with the user
while true; do
  # --- Print message ---
  echo ""
  echo -e "${YELLOW} - Please provide the Kubernetes minor version to install (e.g. 1.31):${NC}"
  echo -e "${YELLOW}   The latest available patch release within this minor version will be installed automatically.${NC}"
  echo -e "${RED}   Note: this script only checks the format (X.Y). Make sure the minor version you enter is real and available on pkgs.k8s.io - an invalid version will break the installation later.${NC}"

  # --- Read the version value ---
  read -rp "   Enter minor version: " VERSION_INPUT

  # --- Sanity check: value must match X.Y format ---
  if [[ ! "$VERSION_INPUT" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}   Invalid input. Version must be in the format X.Y (e.g. 1.31).${NC}"
    continue
  fi

  # --- Print summary + confirm ---
  echo "   Please confirm the Kubernetes minor version: Your entry is $VERSION_INPUT"
  if confirm_yn "   Is this correct? (Y/N): "; then
    echo -e "${CYAN}   Kubernetes minor version confirmed. Proceeding...${NC}"
    K8S_MAJOR_MINOR="$VERSION_INPUT"
    break
  else
    echo -e "${CYAN}   Re-entering Kubernetes minor version...${NC}"
  fi
done

    #------------------------------------------------------------------------------

# Check the running OS and check its compitability
echo ""
echo -e "${YELLOW} - Detecting the operating system running on this node...${NC}"

# Check that /etc/os-release exists, needed to detect the OS
if [[ ! -f /etc/os-release ]]; then
  echo -e "${RED}   FAILED: /etc/os-release not found - cannot detect the operating system.${NC}"
  echo -e "${RED}   ------- Please Check this issue and rerun this script.${NC}"
  exit 1
fi

# Source the os-release file to get OS identification variables
source /etc/os-release

# Store the OS ID in a variable for later use
OS_ID="${ID:-}"

# Determine the OS family based on the OS ID
if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
  OS_FAMILY="debian"
elif [[ "$OS_ID" == "rhel" || "$OS_ID" == "rocky" || "$OS_ID" == "almalinux" || "$OS_ID" == "centos" ]]; then
  OS_FAMILY="rhel"
else
  echo -e "${RED}   FAILED: Unsupported OS ($OS_ID). This script supports Ubuntu/Debian and RHEL/Rocky/AlmaLinux/CentOS only.${NC}"
  exit 1
fi

# Print the detected OS to the user
echo -e "${GREEN}   SUCCESS: Detected OS - ${PRETTY_NAME} (family: ${OS_FAMILY})${NC}"

    #------------------------------------------------------------------------------

#=========================================================================================

#-------------------------------------------------------------
# Print All Collected Info And Confirm Before Proceeding
#-------------------------------------------------------------

# Print a summary of all information collected from the user so far
echo ""
echo -e "${GREEN} Part 2: - Confirm Collected Info Before Installation:${NC}"
echo -e "${GREEN} -------------------------------------------------------${NC}"
echo ""
echo "   ----------------------------------------"
echo "   Master Node Count      : $MASTER_COUNT"
echo "   This Node Role         : $NODE_ROLE"

# --- Print master-specific info if this node is a master ---
if [[ "$NODE_ROLE" == "master" ]]; then
  echo "   First Master Node      : $IS_FIRST_MASTER"
fi

# --- Print endpoint info if this node collected one (not first master in single-master cluster) ---
if [[ -n "${MASTER_ENDPOINT:-}" ]]; then
  echo "   Master/LB Endpoint     : $MASTER_ENDPOINT"
fi

# --- Print join command info if this node collected one (not the first master) ---
if [[ -n "${JOIN_COMMAND:-}" ]]; then
  echo "   Join Command           : $JOIN_COMMAND"
fi

# --- Print CNI and CIDR info if this node is the first master ---
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "yes" ]]; then
  echo "   CNI Selection          : $CNI_CHOICE"
  echo "   Pod CIDR               : $POD_CIDR"
  echo "   Service CIDR           : $SVC_CIDR"
fi

# --- Print Kubernetes Version ---
echo "   Kubernetes Version     : $K8S_MAJOR_MINOR"

# --- Print Os Family Type ---
echo "   OS Family              : $OS_FAMILY"

echo "   ----------------------------------------"
echo ""

# Ask the user to confirm before any installation steps begin
if confirm_yn "   All info above is correct, proceed with installation? (Y/N): "; then
  echo -e "${CYAN}   Information confirmed. Starting installation...${NC}"
else
  echo -e "${RED}   ------------------------------------------------------------------------------------.${NC}"
  echo -e "${RED}   Provide information is confirmed incorrect.${NC}"
  echo -e "${RED}   Installation cancelled. Please rerun this script and provide the correct information.${NC}"
  echo -e "${RED}   ------------------------------------------------------------------------------------.${NC}"
  exit 1
fi

#=========================================================================================

echo ""
echo -e "${GREEN} ------------------------------------${NC}"
echo -e "${GREEN} ------ Installation Starting -------${NC}"
echo -e "${GREEN} ------------------------------------${NC}"
echo ""

#=========================================================================================

echo -e "${GREEN} Part 3: - Pre-Flight OS Preparation:${NC}"
echo -e "${GREEN} ------------------------------------${NC}"
echo ""

# Disable Swap
#----------------------
# Print message that swap is being disabled
echo -e "${YELLOW} - Disabling swap...${NC}"

# Turn off all active swap immediately
swapoff -a

# Comment out any swap entries in /etc/fstab so swap stays off after a reboot
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

# Confirm swap has been disabled
echo -e "${CYAN}       Swap disabled.${NC}"

    #------------------------------------------------------------------------------

# Load Required Kernel Modules
#-----------------------------
# Print message that kernel modules are being configured
echo ""
echo -e "${YELLOW} - Loading required kernel modules (overlay, br_netfilter)...${NC}"

# Write a config file so these modules load automatically on every boot
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Load the overlay module immediately for this session
modprobe overlay

# Load the br_netfilter module immediately for this session
modprobe br_netfilter

# Confirm the kernel modules are loaded
echo -e "${CYAN}       Kernel modules loaded.${NC}"

    #------------------------------------------------------------------------------

# Apply Required Sysctl Parameters
#---------------------------------
# Print message that sysctl parameters are being applied
echo ""
echo -e "${YELLOW} - Applying required sysctl parameters...${NC}"

# Write the required sysctl parameters to a dedicated config file
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply the sysctl parameters immediately without needing a reboot
sysctl --system > /dev/null

# Confirm the sysctl parameters are applied
echo -e "${CYAN}       Sysctl parameters applied.${NC}"

#=========================================================================================

echo ""
echo -e "${GREEN} Part 4: - Install Container Runtime (containerd):${NC}"
echo -e "${GREEN} ----------------------------------------------------${NC}"
echo ""

#-------------------------------------------------------------
# Install containerd (Debian Family: Ubuntu/Debian)
#-------------------------------------------------------------

# If this node is Debian family, install containerd using Docker's apt repo
if [[ "$OS_FAMILY" == "debian" ]]; then
  # Print message that containerd installation is starting
  echo ""
  echo -e "${YELLOW} - Installing containerd (Debian family)...${NC}"
  echo ""

  # Update the apt package index
  apt-get update -y

  # Install packages required to add a new apt repo over HTTPS
  apt-get install -y apt-transport-https ca-certificates curl gnupg

  # Create the apt keyrings directory if it does not already exist
  if [[ ! -d /etc/apt/keyrings ]]; then
    mkdir -p -m 755 /etc/apt/keyrings
  fi

  # Download Docker's GPG key
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

  # Make the GPG key file readable by all users
  chmod a+r /etc/apt/keyrings/docker.asc

  # Source os-release again to get the Ubuntu/Debian codename for the repo line
  # shellcheck disable=SC1091
  source /etc/os-release

  # Add Docker's apt repo, which provides the containerd.io package
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

  # Update the apt package index again now the new repo has been added
  apt-get update -y

  # Install containerd
  apt-get install -y containerd.io
fi

    #------------------------------------------------------------------------------

#-------------------------------------------------------------
# Install containerd (RHEL Family: RHEL/Rocky/AlmaLinux/CentOS)
#-------------------------------------------------------------

# If this node is RHEL family, install containerd using Docker's dnf repo
if [[ "$OS_FAMILY" == "rhel" ]]; then
  # Print message that containerd installation is starting
  echo ""
  echo -e "${YELLOW} - Installing containerd (RHEL family)...${NC}"
  echo ""

  # Install the dnf plugin needed to add a new repo
  dnf install -y dnf-plugins-core

  # Add Docker's RHEL repo, which provides the containerd.io package
  dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

  # Install containerd
  dnf install -y containerd.io
fi

    #------------------------------------------------------------------------------

#-------------------------------------------------------------
# Configure containerd (Both OS Families)
#-------------------------------------------------------------

# Print message that containerd is being configured
echo ""
echo -e "${YELLOW} - Configuring containerd...${NC}"
echo ""

# Create the containerd config directory if it does not already exist
mkdir -p /etc/containerd

# Generate the default containerd config file
containerd config default > /etc/containerd/config.toml

# Set SystemdCgroup to true, required for kubelet to work correctly with containerd
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Verify SystemdCgroup was actually set to true; fail loudly if not
if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
  echo -e "${RED}   FAILED: Could not confirm SystemdCgroup=true in containerd config. Check /etc/containerd/config.toml manually.${NC}"
  exit 1
fi

# Enable containerd to start automatically on boot, and start it now
systemctl enable --now containerd

# Restart containerd to apply the configuration changes
systemctl restart containerd

# Confirm containerd has been installed and configured
echo -e "${GREEN}   containerd installed and configured (SystemdCgroup=true).${NC}"

#=========================================================================================

echo ""
echo -e "${GREEN} Part 5: - Install kubelet, kubeadm, kubectl:${NC}"
echo -e "${GREEN} ------------------------------------------------${NC}"
echo ""

#-------------------------------------------------------------
# Install kubelet, kubeadm, kubectl (Debian Family: Ubuntu/Debian)
#-------------------------------------------------------------

# If this node is Debian family, install the Kubernetes packages using the pkgs.k8s.io apt repo
if [[ "$OS_FAMILY" == "debian" ]]; then
  # Print message that installation is starting
  echo ""
  echo -e "${YELLOW} - Installing kubelet, kubeadm, kubectl (Debian family)...${NC}"
  echo ""

  # Update the apt package index
  apt-get update -y

  # Install packages needed to use the Kubernetes apt repository
  apt-get install -y apt-transport-https ca-certificates curl gpg

  # Create the apt keyrings directory if it does not already exist
  if [[ ! -d /etc/apt/keyrings ]]; then
    mkdir -p -m 755 /etc/apt/keyrings
  fi

  # Download the Kubernetes package repository signing key
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  # Add the Kubernetes apt repository (overwrites any existing configuration)
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list

  # Update the apt package index again now the new repo has been added
  apt-get update -y

  # Install kubelet, kubeadm, and kubectl
  apt-get install -y kubelet kubeadm kubectl

  # Pin these packages so they are not upgraded by a normal apt upgrade
  apt-mark hold kubelet kubeadm kubectl

  # Enable the kubelet service before running kubeadm
  systemctl enable --now kubelet
fi

    #------------------------------------------------------------------------------

#-------------------------------------------------------------
# Install kubelet, kubeadm, kubectl (RHEL Family: RHEL/Rocky/AlmaLinux/CentOS)
#-------------------------------------------------------------

# If this node is RHEL family, install the Kubernetes packages using the pkgs.k8s.io yum repo
if [[ "$OS_FAMILY" == "rhel" ]]; then
  # Print message that installation is starting
  echo ""
  echo -e "${YELLOW} - Installing kubelet, kubeadm, kubectl (RHEL family)...${NC}"
  echo ""

  # Set SELinux to permissive mode, required for container network plugins
  setenforce 0

  # Update the SELinux config file so this survives a reboot
  sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

  # Add the Kubernetes yum repository (overwrites any existing configuration)
  cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

  # Detect the DNF major version, since DNF4 and DNF5 use different exclude flag syntax
  DNF_MAJOR_VERSION=$(dnf --version 2>/dev/null | head -n1 | grep -oE '^[0-9]+')

  # Get the OS major version, needed to check for RHEL/Rocky/Alma 10+
  OS_MAJOR_VERSION="${VERSION_ID%%.*}"

  # Use the DNF5 exclude flag syntax if DNF5 is detected, otherwise use the DNF4 syntax
  if [[ "$DNF_MAJOR_VERSION" == "5" ]]; then
    EXCLUDE_FLAG="--setopt=disable_excludes=kubernetes"
  else
    EXCLUDE_FLAG="--disableexcludes=kubernetes"
  fi

  # On RHEL/Rocky/Alma 10 and later, also disable weak deps to avoid pulling in iptables
  WEAK_DEPS_FLAG=""
  if [[ "$OS_MAJOR_VERSION" =~ ^[0-9]+$ ]] && (( OS_MAJOR_VERSION >= 10 )); then
    WEAK_DEPS_FLAG="--setopt=install_weak_deps=False"
  fi

  # Install kubelet, kubeadm, and kubectl using dnf with the correct flags for this system
  # shellcheck disable=SC2086
  dnf install -y kubelet kubeadm kubectl $EXCLUDE_FLAG $WEAK_DEPS_FLAG

  # Enable the kubelet service before running kubeadm
  systemctl enable --now kubelet
fi

#=========================================================================================

echo ""
echo -e "${GREEN} Part 6: - Initialize Or Join The Kubernetes Cluster:${NC}"
echo -e "${GREEN} --------------------------------------------------------${NC}"
echo ""

#-------------------------------------------------------------
# Initialize The Cluster (First Master Node Only)
#-------------------------------------------------------------

# If this is the first master node, run kubeadm init to create the cluster
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "yes" ]]; then
  # Print message that cluster initialization is starting
  echo ""
  echo -e "${YELLOW} - Initializing the cluster with kubeadm init...${NC}"
  echo ""

  # Build the base kubeadm init arguments
  INIT_ARGS=(--kubernetes-version="stable-${K8S_MAJOR_MINOR}" --pod-network-cidr="${POD_CIDR}" --service-cidr="${SVC_CIDR}")

  # If there are 3 masters, add the control-plane endpoint and upload-certs flags
  if [[ "$MASTER_COUNT" == "3" ]]; then
    INIT_ARGS+=(--control-plane-endpoint="${MASTER_ENDPOINT}:6443" --upload-certs)
  fi

  # Run kubeadm init and save the output to a file so the join commands can be extracted later
  kubeadm init "${INIT_ARGS[@]}" | tee /root/kubeadm-init-output.log

  # Confirm cluster initialization completed
  echo -e "${GREEN}   Cluster initialized successfully.${NC}"

  # Print the join commands so the user can copy them for the next nodes
  echo ""
  echo -e "${YELLOW} - IMPORTANT: save the join command(s) below - also saved to /root/kubeadm-init-output.log:${NC}"
  echo "   ----------------------------------------"
  grep -A2 "kubeadm join" /root/kubeadm-init-output.log || true
  echo "   ----------------------------------------"

  # Warn the user about which join command applies, and the certificate-key expiry
  if [[ "$MASTER_COUNT" == "1" ]]; then
    echo -e "${YELLOW}   Only 1 master was selected - the printed join command is WORKER-ONLY.${NC}"
  else
    echo -e "${YELLOW}   Two join commands were printed above: one for WORKERS, one for CONTROL-PLANE nodes (--control-plane --certificate-key). The certificate-key is only valid for 2 hours.${NC}"
  fi
fi

    #------------------------------------------------------------------------------

#-------------------------------------------------------------
# Join The Cluster (Joining Master Or Worker Node)
#-------------------------------------------------------------

# If this is a joining master node or a worker node, run the join command provided by the user
if [[ ( "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "no" ) || "$NODE_ROLE" == "worker" ]]; then
  # Print message that this node is joining the cluster
  echo ""
  echo -e "${YELLOW} - Joining this node to the cluster...${NC}"
  echo ""

  # Run the join command collected earlier from the user
  eval "$JOIN_COMMAND"

  # Confirm the node joined the cluster
  echo -e "${GREEN}   Node joined the cluster successfully.${NC}"
fi

#=========================================================================================

#-------------------------------------------------------------
# Configure kubeconfig System-Wide (Master Nodes Only - First Or Joining)
#-------------------------------------------------------------

# If this is a master node (first or joining), set up kubeconfig for this session and system-wide
if [[ "$NODE_ROLE" == "master" ]]; then
  echo ""
  echo -e "${GREEN} Part 7: - Configure kubeconfig:${NC}"
  echo -e "${GREEN} -----------------------------------${NC}"
  echo ""

  # Print message that kubeconfig setup is starting
  echo ""
  echo -e "${YELLOW} - Setting up kubeconfig...${NC}"
  echo ""

  # Create the .kube directory in this user's home directory
  mkdir -p "$HOME/.kube"

  # Copy the admin kubeconfig generated by kubeadm - this makes kubectl work immediately in this session
  cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"

  # Set ownership of the kubeconfig file to the current user
  chown "$(id -u):$(id -g)" "$HOME/.kube/config"

  # Make the admin kubeconfig readable by all local users, for use by anyone who logs in later
  chmod 644 /etc/kubernetes/admin.conf

  # Create a profile.d script so KUBECONFIG is exported automatically for every future login shell
  cat <<EOF > /etc/profile.d/kubeconfig.sh
export KUBECONFIG=/etc/kubernetes/admin.conf
EOF

  # Make the profile.d script executable
  chmod +x /etc/profile.d/kubeconfig.sh

  # Confirm kubeconfig setup completed
  echo -e "${GREEN}   kubeconfig set up at $HOME/.kube/config - kubectl is ready to use in this session.${NC}"
  echo -e "${GREEN}   Also available system-wide at /etc/kubernetes/admin.conf for any future login sessions.${NC}"
fi

#=========================================================================================

#-------------------------------------------------------------
# Install Helm (Master Nodes Only - First Or Joining)
#-------------------------------------------------------------

# If this is a master node (first or joining), install Helm
if [[ "$NODE_ROLE" == "master" ]]; then
  echo ""
  echo -e "${GREEN} Part 8: - Install Helm:${NC}"
  echo -e "${GREEN} ---------------------------${NC}"
  echo ""

  # Print message that Helm installation is starting
  echo -e "${YELLOW} - Installing Helm...${NC}"
  echo ""

  # Download the official Helm install script
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm-3.sh

  # Make the install script executable
  chmod +x /tmp/get-helm-3.sh

  # Run the install script
  /tmp/get-helm-3.sh

  # Remove the install script now that Helm is installed
  rm -f /tmp/get-helm-3.sh

  # Confirm Helm installation completed
  echo -e "${GREEN}   Helm installed: $(helm version --short 2>/dev/null || echo 'version check failed')${NC}"
fi

#=========================================================================================

#-------------------------------------------------------------
# Install CNI (First Master Node Only)
#-------------------------------------------------------------

# If this is the first master node, install the chosen CNI
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "yes" ]]; then
  echo ""
  echo -e "${GREEN} Part 9: - Install CNI:${NC}"
  echo -e "${GREEN} --------------------------${NC}"
  echo ""

  # --- Install Calico ---
  if [[ "$CNI_CHOICE" == "calico" ]]; then
        # Print message that Calico installation is starting
    echo -e "${YELLOW} - Installing Calico...${NC}"
    echo ""

    # Add and refresh the Tigera Helm repo
    helm repo add projectcalico https://docs.tigera.io/calico/charts 
    helm repo update

    # Install the Calico CRDs (a separate chart from the operator itself)
    helm template calico-crds projectcalico/crd.projectcalico.org.v1 | kubectl apply --server-side -f -

    # Install the Tigera operator and Calico via Helm, using the Pod CIDR set earlier
    helm install calico projectcalico/tigera-operator \
      --namespace tigera-operator \
      --create-namespace \
      --set installation.cni.type=Calico \
      --set "installation.calicoNetwork.ipPools[0].cidr=${POD_CIDR}" \
      --set "installation.calicoNetwork.ipPools[0].encapsulation=VXLAN"

    # Fail loudly if the Helm install did not succeed
    if [[ $? -ne 0 ]]; then
      echo -e "${RED}   FAILED: Calico Helm install did not complete.${NC}"
      exit 1
    fi

    # Wait for Calico to report ready before moving on
    until kubectl get tigerastatus/calico; do sleep 2; done
    kubectl wait tigerastatus/calico --for=condition=Available --timeout=300s

    # Fail loudly if Calico did not become available
    if [[ $? -ne 0 ]]; then
      echo -e "${RED}   FAILED: Calico did not become available in time.${NC}"
      exit 1
    fi

    # Confirm Calico installation completed
    echo -e "${GREEN}   Calico installed successfully, Pod CIDR set to ${POD_CIDR}.${NC}"
  fi

# --- Install Cilium ---
  if [[ "$CNI_CHOICE" == "cilium" ]]; then
    # Print message that Cilium installation is starting
    echo -e "${YELLOW} - Installing Cilium via Helm...${NC}"
    echo ""

    # Add and refresh the Cilium Helm repo
    helm repo add cilium https://helm.cilium.io/
    helm repo update

    # Install Cilium via Helm, using the Pod CIDR set earlier
    helm install cilium cilium/cilium --namespace kube-system \
      --set "ipam.operator.clusterPoolIPv4PodCIDRList={${POD_CIDR}}" \
      --set routingMode=tunnel \
      --set tunnelProtocol=vxlan

    # Fail loudly if the Helm install did not succeed
    if [[ $? -ne 0 ]]; then
      echo -e "${RED}   FAILED: Cilium Helm install did not complete.${NC}"
      exit 1
    fi

    # Wait for the Cilium DaemonSet to be ready before moving on
    echo -e "${YELLOW} - Waiting for Cilium to become available...${NC}"
    kubectl -n kube-system rollout status daemonset/cilium --timeout=300s

    # Fail loudly if Cilium did not become available
    if [[ $? -ne 0 ]]; then
      echo -e "${RED}   FAILED: Cilium did not become available in time.${NC}"
      exit 1
    fi

    # Confirm Cilium installation completed
    echo -e "${GREEN}   Cilium installed via Helm, Pod CIDR set to ${POD_CIDR}.${NC}"
  fi
fi

#=========================================================================================

echo ""
echo -e "${GREEN} ==================================================${NC}"

echo ""
echo -e "${GREEN} This script has completed successfully${NC}"
echo -e "${GREEN} --------------------------------------${NC}"
echo ""

#-------------------------------------------------------------
# Re-Print Join Commands (First Master Node Only)
#-------------------------------------------------------------

# If this is the first master node, re-print the join command(s) as a final reminder
if [[ "$NODE_ROLE" == "master" && "$IS_FIRST_MASTER" == "yes" ]]; then
  echo -e "${YELLOW} - Reminder: join command(s) for other nodes (also saved to /root/kubeadm-init-output.log):${NC}"
  echo "   ----------------------------------------"
  grep -A2 "kubeadm join" /root/kubeadm-init-output.log || true
  if [[ "$MASTER_COUNT" == "1" ]]; then
    echo -e "${YELLOW}   Only 1 master was selected - the printed join command is WORKER-ONLY.${NC}"
  else
    echo -e "${YELLOW}   Two join commands were printed above: one for WORKERS, one for CONTROL-PLANE nodes (--control-plane --certificate-key). The certificate-key is only valid for 2 hours.${NC}"
  fi
  echo "   ----------------------------------------"
fi

echo ""
echo -e "${GREEN} -----------------------------------------${NC}"
echo -e "${GREEN} Please Note: If kubectl did not work, you may be using a different user.${NC}"
echo -e "${GREEN}              You can either logout and login again and it will then work.${NC}"
echo -e "${GREEN}              Or apply the following.${NC}"
echo -e '${GREEN}              mkdir -p "$HOME/.kube"${NC}'
echo -e '${GREEN}              cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"${NC}'
echo -e '${GREEN}              chown "$(id -u):$(id -g)" "$HOME/.kube/config"${NC}'
echo -e "${GREEN} Enjoy${NC}"
echo -e "${GREEN} -----------------------------------------${NC}"
echo ""


# Print a closing message confirming this node's bootstrap is complete
echo ""
echo -e "${GREEN} -----------------------------------------${NC}"
echo -e "${GREEN} Node bootstrap complete.${NC}"
echo -e "${GREEN} Enjoy${NC}"
echo -e "${GREEN} -----------------------------------------${NC}"
echo ""
echo -e "${GREEN} ==================================================${NC}"

#=========================================================================================