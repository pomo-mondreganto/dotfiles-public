# zcache: cache the stdout of a command, source it, and re-run only when
# the command string changes or any named anchor file is newer than the
# cache. Purpose-built replacement for znap's `znap eval` that lives
# entirely in zsh and honours XDG_CACHE_HOME.
#
# Usage:
#   zcache <name> <command> [<anchor-path>...]
#
# Arguments:
#   name    Cache identifier used as the basename. Any short string is fine
#           (e.g. "mise-activate", "fzf", "atuin").
#   command Full shell command whose stdout is shell code to be sourced.
#   anchor  Optional file(s) whose mtime triggers a rebuild when newer
#           than the cache. Typically pass the binary being wrapped
#           ("${commands[mise]}") so upgrading the tool invalidates the
#           cache automatically. You can pass a config file too.
#
# Caches live under ${XDG_CACHE_HOME:-$HOME/.cache}/zsh-eval/<name>.zsh
# and are byte-compiled (.zwc) for near-zero re-source cost.
#
# Examples (place in .zshrc or common.zsh after this file is sourced):
#   zcache mise-activate 'mise activate zsh'          ${commands[mise]}
#   zcache fzf           'fzf --zsh'                  ${commands[fzf]}
#   zcache atuin         'atuin init zsh --disable-up-arrow' ${commands[atuin]}
#   zcache brew-shellenv '/opt/homebrew/bin/brew shellenv'   /opt/homebrew/bin/brew
#   zcache starship      'starship init zsh --print-full-init' ${commands[starship]}
#   zcache direnv        'direnv hook zsh'            ${commands[direnv]}
#   zcache zoxide        'zoxide init zsh'            ${commands[zoxide]}
#
# Manual invalidation: `rm ~/.cache/zsh-eval/<name>.zsh*`.
zcache() {
  emulate -L zsh
  setopt local_options pipe_fail

  if (( $# < 2 )); then
    print -u2 'zcache: usage: zcache <name> <command> [<anchor>...]'
    return 2
  fi

  local name=$1 cmd=$2
  shift 2
  local -a anchors=( "$@" )

  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-eval"
  local cache="$cache_dir/${name}.zsh"
  local header="# zcache[${name}]: ${(q+)cmd}"

  local need_regen=1
  if [[ -s $cache ]]; then
    local first=''
    IFS= read -r first < $cache
    if [[ $first == $header ]]; then
      need_regen=0
      local anchor
      for anchor in $anchors; do
        [[ -n $anchor && -e $anchor && $anchor -nt $cache ]] && { need_regen=1; break; }
      done
    fi
  fi

  if (( need_regen )); then
    mkdir -p -- $cache_dir || return 1
    {
      print -r -- $header
      eval "$cmd"
    } >| $cache || return 1
    # Byte-compile so the next `source` reads the compiled form.
    # `source`/`.` in zsh automatically prefers a newer .zwc sibling.
    zcompile -R -- $cache 2>/dev/null
  fi

  source $cache
}

# zcomp: shorthand for caching `<bin> completion zsh` output. Cobra/urfave-style
# binaries ship that subcommand; we cache the script and source it. Anchored on
# the binary path so an upgrade invalidates. Silently no-ops for missing binaries.
# Usage: zcomp kubectl helm pinus
zcomp() {
  local bin
  for bin in "$@"; do
    (( ${+commands[$bin]} )) && zcache "$bin" "$bin completion zsh" ${commands[$bin]}
  done
}
