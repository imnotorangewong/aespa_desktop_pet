#!/bin/zsh
set -eu
LABEL="local.imnotorange.purplepet.autostart"
DOMAIN="gui/$(id -u)"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${2:-$SCRIPT_DIR/紫色小伙伴.app}"

case "${1:-install}" in
  install)
    [[ -x "$APP/Contents/MacOS/PurplePet" ]] || { echo "找不到桌宠应用：$APP"; exit 1; }
    mkdir -p "$AGENTS"
    TMP="$(mktemp "$AGENTS/.purplepet.XXXXXX")"
    trap 'if [[ -n "${TMP:-}" ]]; then rm -f "$TMP"; fi' EXIT
    /usr/bin/plutil -create xml1 "$TMP"
    /usr/bin/plutil -insert Label -string "$LABEL" "$TMP"
    /usr/bin/plutil -insert ProgramArguments -json '["/usr/bin/open","-g","-a"]' "$TMP"
    /usr/bin/plutil -insert ProgramArguments.3 -string "$APP" "$TMP"
    /usr/bin/plutil -insert RunAtLoad -bool YES "$TMP"
    /usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$TMP"
    /usr/bin/plutil -lint "$TMP"
    chmod 644 "$TMP"
    if /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      /bin/launchctl bootout "$DOMAIN/$LABEL"
    fi
    mv "$TMP" "$PLIST"
    TMP=""
    /bin/launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "已启用：现在启动桌宠，以后每次登录此账户时自动启动。"
    ;;
  uninstall)
    if /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      /bin/launchctl bootout "$DOMAIN/$LABEL"
    fi
    if [[ -e "$PLIST" ]]; then
      mkdir -p "$HOME/.Trash"
      mv "$PLIST" "$HOME/.Trash/$LABEL.$(date +%Y%m%d%H%M%S).plist"
    fi
    echo "已取消自动启动；正在运行的桌宠请右键退出。"
    ;;
  *)
    echo "用法：zsh pet-autostart.sh [install|uninstall] [app-path]"
    exit 2
    ;;
esac

