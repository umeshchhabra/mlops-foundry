#!/usr/bin/env bash
# Generic remote-key installer; host and user are explicit arguments.
set -euo pipefail

host_name=""
user_name=""
key_path="${MLOPS_SSH_KEY_PATH:-$HOME/.ssh/mlops_foundry_ed25519}"

usage() {
  cat <<'EOF'
Usage: ./scripts/install-ssh-key.sh --host HOST --user USER [--key-path PATH]

Creates an ED25519 key if needed, adds its public half to the remote account,
then verifies key-based login. The remote host prompts once for its password;
that password is not stored by this helper.
EOF
}

while (($#)); do
  case "$1" in
    --host)
      host_name="${2:?--host requires a value}"
      shift 2
      ;;
    --user)
      user_name="${2:?--user requires a value}"
      shift 2
      ;;
    --key-path)
      key_path="${2:?--key-path requires a value}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$host_name" || -z "$user_name" ]]; then
  usage >&2
  exit 2
fi
for command in ssh ssh-keygen; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  }
done

mkdir -p "$(dirname "$key_path")"
chmod 700 "$(dirname "$key_path")"
if [[ ! -f "$key_path" ]]; then
  ssh-keygen -t ed25519 -a 64 -f "$key_path" -C 'mlops-foundry' -N ''
fi
if [[ ! -f "$key_path.pub" ]]; then
  ssh-keygen -y -f "$key_path" > "$key_path.pub"
fi

public_key="$(<"$key_path.pub")"
printf '%s\n' "$public_key" |
  ssh -o StrictHostKeyChecking=ask \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o PubkeyAuthentication=no \
    "$user_name@$host_name" \
    'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; read -r key; grep -qxF "$key" ~/.ssh/authorized_keys || printf "%s\n" "$key" >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys'

ssh -i "$key_path" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o PreferredAuthentications=publickey "$user_name@$host_name" \
  'echo SSH key authentication works'
printf 'SSH key authentication configured for %s@%s.\n' "$user_name" "$host_name"
