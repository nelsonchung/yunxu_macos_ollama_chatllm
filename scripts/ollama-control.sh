#!/bin/zsh

set -euo pipefail

APP_NAME="Ollama"

print_help() {
  cat <<'EOF'
Usage:
  ./scripts/ollama-control.sh status
  ./scripts/ollama-control.sh unload MODEL
  ./scripts/ollama-control.sh unload-all
  ./scripts/ollama-control.sh quit-app
  ./scripts/ollama-control.sh stop-service
  ./scripts/ollama-control.sh help

Commands:
  status         Show running models and Ollama-related processes.
  unload MODEL   Unload one running model via `ollama stop MODEL`.
  unload-all     Unload all running models currently shown by `ollama ps`.
  quit-app       Ask macOS to quit Ollama.app cleanly.
  stop-service   Stop Ollama background processes started by the app or `ollama serve`.
  help           Show this help message.

Examples:
  ./scripts/ollama-control.sh unload qwen3.5:2b
  ./scripts/ollama-control.sh unload-all
  ./scripts/ollama-control.sh quit-app
EOF
}

require_ollama() {
  if ! command -v ollama >/dev/null 2>&1; then
    echo "Error: ollama command not found." >&2
    exit 1
  fi
}

show_status() {
  require_ollama

  echo "== ollama ps =="
  ollama ps || true
  echo
  echo "== Ollama processes =="
  ps aux | grep -i "[o]llama" || true
}

unload_model() {
  require_ollama

  local model="${1:-}"
  if [[ -z "${model}" ]]; then
    echo "Error: please provide a model name." >&2
    echo "Example: ./scripts/ollama-control.sh unload qwen3.5:2b" >&2
    exit 1
  fi

  echo "Unloading model: ${model}"
  ollama stop "${model}"
}

unload_all_models() {
  require_ollama

  local models
  models="$(ollama ps 2>/dev/null | awk 'NR>1 && NF>0 {print $1}')"

  if [[ -z "${models}" ]]; then
    echo "No running models found."
    return
  fi

  echo "${models}" | while IFS= read -r model; do
    [[ -z "${model}" ]] && continue
    echo "Unloading model: ${model}"
    ollama stop "${model}" || true
  done
}

quit_app() {
  if osascript -e "tell application \"System Events\" to (name of processes) contains \"${APP_NAME}\"" | grep -q "true"; then
    echo "Quitting ${APP_NAME}.app"
    osascript -e "tell application \"${APP_NAME}\" to quit"
  else
    echo "${APP_NAME}.app is not running."
  fi
}

stop_service() {
  local found=0

  if pgrep -f "/Applications/Ollama.app/Contents/Resources/ollama serve" >/dev/null 2>&1; then
    echo "Stopping ollama serve"
    pkill -f "/Applications/Ollama.app/Contents/Resources/ollama serve" || true
    found=1
  fi

  if pgrep -f "/Applications/Ollama.app/Contents/Resources/ollama runner" >/dev/null 2>&1; then
    echo "Stopping ollama runner"
    pkill -f "/Applications/Ollama.app/Contents/Resources/ollama runner" || true
    found=1
  fi

  if pgrep -f "/Applications/Ollama.app/Contents/MacOS/Ollama" >/dev/null 2>&1; then
    echo "Stopping Ollama.app process"
    pkill -f "/Applications/Ollama.app/Contents/MacOS/Ollama" || true
    found=1
  fi

  if pgrep -f "ollama serve" >/dev/null 2>&1; then
    echo "Stopping generic ollama serve"
    pkill -f "ollama serve" || true
    found=1
  fi

  if pgrep -f "ollama runner" >/dev/null 2>&1; then
    echo "Stopping generic ollama runner"
    pkill -f "ollama runner" || true
    found=1
  fi

  if [[ "${found}" -eq 0 ]]; then
    echo "No Ollama background processes found."
  fi
}

main() {
  local command="${1:-help}"

  case "${command}" in
    status)
      show_status
      ;;
    unload)
      unload_model "${2:-}"
      ;;
    unload-all)
      unload_all_models
      ;;
    quit-app)
      quit_app
      ;;
    stop-service)
      stop_service
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      echo "Unknown command: ${command}" >&2
      echo >&2
      print_help >&2
      exit 1
      ;;
  esac
}

main "$@"
