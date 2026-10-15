# Editable shell configuration. Packages and plugin paths are managed in home.nix.
typeset -U path cdpath fpath manpath
path=("/etc/profiles/per-user/$USER/bin" /opt/homebrew/bin $path)
for profile in ${(z)NIX_PROFILES}; do
  fpath+=($profile/share/zsh/site-functions $profile/share/zsh/$ZSH_VERSION/functions $profile/share/zsh/vendor-completions)
done

HELPDIR="$HOME/.local/share/zsh-packages/zsh/share/zsh/$ZSH_VERSION/help"

# Add plugin directories to PATH and fpath
plugin_dirs=(
  fzf-tab
)
for plugin_dir in "${plugin_dirs[@]}"; do
  path+="$HOME/.local/share/zsh-packages/$plugin_dir"
  fpath+="$HOME/.local/share/zsh-packages/$plugin_dir"
done
unset plugin_dir plugin_dirs


autoload -U compinit && compinit
source "$HOME/.local/share/zsh-packages/autosuggestions"/share/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history)


# Source plugins
plugins=(
  fzf-tab/share/fzf-tab/fzf-tab.plugin.zsh
)
for plugin in "${plugins[@]}"; do
  [[ -f "$HOME/.local/share/zsh-packages/$plugin" ]] && source "$HOME/.local/share/zsh-packages/$plugin"
done
unset plugin plugins

# Shared history across interactive shells.
HISTSIZE="10000"
SAVEHIST="10000"

HISTFILE="$HOME/.zsh_history"
mkdir -p "$(dirname "$HISTFILE")"

if [[ $options[zle] = on ]]; then
  source <(fzf --zsh)
fi

# Set shell options
set_opts=(
  HIST_FCNTL_LOCK HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY autocd
  NO_APPEND_HISTORY NO_EXTENDED_HISTORY NO_HIST_EXPIRE_DUPS_FIRST
  NO_HIST_FIND_NO_DUPS NO_HIST_IGNORE_ALL_DUPS NO_HIST_SAVE_NO_DUPS
)
for opt in "${set_opts[@]}"; do
  setopt "$opt"
done
unset opt set_opts

if [[ $TERM != "dumb" ]]; then
  eval "$(starship init zsh)"
fi

# EDITOR=nvim would otherwise make zsh pick the vi keymap
bindkey -e
bindkey '^f' autosuggest-accept
bindkey "^ " fzf-tab-complete

# ---- PATH (carried over from pre-nix zshrc) ----
export PATH="$HOME/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/Dev/pocus/development/scripts:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
export PATH="$HOME/.volta/bin:$PATH"
export PATH="$HOME/.nvm/versions/node/v24.4.1/bin:$PATH"

# ---- Environment ----
export EDITOR="nvim"
export MANPAGER='nvim +Man!'
# Linux sets LC_ALL in .zshenv.
if [[ $OSTYPE != linux* ]]; then
  export LC_ALL=en_US.UTF-8
fi
export AWS_PAGER=""
export NEXT_PUBLIC_WORKSPACE_PREFIX="colby"
export NODE_OPTIONS="--max-old-space-size=8192"
ulimit -n 10240

# ---- FZF ----
export FZF_DEFAULT_COMMAND='rg --files --hidden'
export FZF_DEFAULT_OPTS='
 --bind ctrl-b:preview-half-page-up,ctrl-f:preview-half-page-down
 --height=60% --layout=reverse'
export CUSTOM_FZF_PREVIEW_OPTS="bat --style=numbers --theme=ansi --color=always --line-range :500 {}"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--preview \"$CUSTOM_FZF_PREVIEW_OPTS\""
export FZF_TMUX_OPTS="-r 75% --multi --reverse"
_fzf_comprun() {
  local command=$1
  shift
  case "$command" in
  v | vim | nvim) fzf "$@" --preview "$CUSTOM_FZF_PREVIEW_OPTS" ;;
  ssh) fzf "$@" --preview 'dig {}' ;;
  *) fzf "$@" ;;
  esac
}

# ---- Completion / fzf-tab ----
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'lsd --color=always $realpath'
zstyle ':fzf-tab:complete:ls:*' fzf-preview 'bat --color=always $realpath'
zstyle ':fzf-tab:complete:*' popup-pad 30 0 fzf-completion-opts --multi
zstyle ':fzf-tab:*' switch-group ',' '.'
zstyle ':fzf-tab:complete:git*:*' continuous-trigger ""

# ---- Functions: git ----
fbr() {
  local branches branch
  branches=$(git branch --all | grep -v HEAD) &&
    branch=$(echo "$branches" |
      fzf-tmux -d $((2 + $(wc -l <<<"$branches"))) +m) &&
    git checkout $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
}
gri() {
  if [ -z "$1" ]; then
    echo "Please provide the number of commits to rebase"
    return 1
  fi
  git rebase -i HEAD~"$1"
}
gwtf() {
  local dir=$(git worktree list | fzf | awk '{print $1}')
  [[ -n "$dir" ]] && cd "$dir"
}
glc() {
  git rev-parse HEAD
  git rev-parse HEAD | pbcopy
}

# ---- Functions: kubectl ----
kp() {
  kubectl get po
}
kpl() {
  pod="$(kubectl get po | tail -n+2 | fzf -n1 --reverse --tac | awk '{print $1}')"
  if [[ -n $pod ]]; then
    kubectl logs --tail=3000 --all-containers=true $pod -f
  fi
}
kplp() {
  pod="$(kubectl get po | tail -n+2 | fzf-tmux -n1 --reverse -r 75% --tac --preview='kubectl logs --tail=20 --all-containers=true {1}' --preview-window=right:50% | awk '{print $1}')"
  if [[ -n $pod ]]; then
    kubectl logs --tail=500 --all-containers=true $pod -f
  fi
}

# ---- Functions: misc ----
kj() {
  kill -9 $(jobs -l | awk '{print $3}')
}
function request-godmode() { lumos request --app-like "Apollo - Godmode Access Request - Temporal" --for-me --length 12h --reason "$*" --wait; }

# Build the latest okfs (github.com/jrnxf/okfs) and install it to ~/.cargo/bin.
# Inside an okfs checkout it builds that checkout as it stands; anywhere else
# it keeps its own clone and pulls main first. `build-okfs <commit>` builds
# that commit instead, and `build-okfs -p` picks the commit with fzf.
# Temporary: okfs gets a pinned package like leaf.nix once it has releases.
build-okfs() {
  local src rev=$1
  src="$(git rev-parse --show-toplevel 2>/dev/null)"
  if ! grep -qs '^name = "okfs"$' "$src/Cargo.toml"; then
    src="$HOME/.cache/okfs-build/okfs"
    if [[ -d $src/.git ]]; then
      git -C "$src" pull --ff-only || return
    else
      git clone git@github.com:jrnxf/okfs.git "$src" || return
    fi
  fi
  if [[ $rev == -p ]]; then
    rev="$(git -C "$src" log --oneline --color=always |
      fzf --ansi --no-sort --reverse --preview "git -C ${(q)src} show --stat --color=always {1}" |
      awk '{print $1}')"
    [[ -n $rev ]] || return
  fi
  local -a from=(--path .)
  if [[ -n $rev ]]; then
    local commit
    commit="$(git -C "$src" rev-parse --verify --quiet "$rev^{commit}")" || {
      print -u2 "build-okfs: no such commit: $rev"
      return 1
    }
    # cargo checks the commit out into its own cache, so the working tree is
    # left alone; sharing target/ keeps the dependencies built.
    from=(--git "file://$src" --rev "$commit")
    local -x CARGO_TARGET_DIR="$src/target"
  fi
  (cd "$src" && nix --extra-experimental-features 'nix-command flakes' develop -c cargo install "${from[@]}" --locked)
}

# homelab ssh picker wrapper (managed by ansible pre-migration)
ssh() {
  if [[ "$1" == "homelab" ]]; then
    shift
    local target
    target="$("$HOME/.local/bin/homelab-ssh-pick")" || return $?
    [[ -n "$target" ]] || return 1
    command ssh "$target" "$@"
  else
    command ssh "$@"
  fi
}

# Logging in to the Linux machine lands in Firstmate. Only a login shell still
# sitting in $HOME moves: commands run over ssh, scp and rsync never read this
# file, and herdr panes and tmux windows keep the directory they were given.
if [[ $OSTYPE == linux* && -o login && $PWD == $HOME && -d ~/firstmate && -z $TMUX && -z $HERDR_ENV ]]; then
  cd ~/firstmate
fi

# ---- Tool initialization ----
[[ $commands[kubectl] ]] && source <(kubectl completion zsh)
[[ $commands[thefuck] ]] && eval "$(thefuck --alias)"
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
_gt_yargs_completions() {
  local reply
  local si=$IFS
  IFS=$'\n' reply=($(COMP_CWORD="$((CURRENT-1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" gt --get-yargs-completions "${words[@]}"))
  IFS=$si
  _describe 'values' reply
}
compdef _gt_yargs_completions gt
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# Keep Homebrew bins first so `tilt` (Homebrew) wins over any `tilt` gem
# shim.
export PATH="/opt/homebrew/bin:$PATH"
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# LeadGenie native Rails (Docker services on localhost)
export MONGO_ENDPOINT="localhost:27021"
export ES_ENDPOINT="localhost:9200"
export REDIS_HOST="localhost"
export REDIS_RATELIMITER_HOST="localhost"
export REDIS_CACHE_URL="redis://localhost:6379/0"
export RAILS_HOST="127.0.0.1:3001"

# Local, untracked overrides (secrets, machine-specific env, etc.)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

alias -- ..='cd ..'
alias -- add='git add .'
alias -- asoff='ZSH_AUTOSUGGEST_STRATEGY=()'
alias -- ason='ZSH_AUTOSUGGEST_STRATEGY=(history completion)'
alias -- bbs='bun run build && bun run start'
alias -- bpf='bun run preflight'
alias -- cat=bat
alias -- cc='claude --dangerously-skip-permissions'
alias -- clear='printf "\33c\e[3J"'
alias -- co=codex
alias -- curltime='curl -w "@$HOME/.curl-format.txt" -o /dev/null -s '
alias -- d-ra='docker rmi -f $(docker images -aq)'
alias -- d-rac='docker rm -f $(docker ps -a -q)'
alias -- d-rav='docker rm -vf $(docker ps -aq)'
alias -- d-sac='docker stop $(docker ps -a -q)'
alias -- d-sp='docker system prune -af --volumes'
alias -- d-srac='d-sac && d-rac'
alias -- dc='git commit -m "$(date +%m/%d/%y\ %H:%M)"'
alias -- dev='cd ~/Dev'
alias -- dot='cd ~/dotfiles'
alias -- gaca='git commit -a --amend --no-edit'
alias -- gca='git commit --amend --no-edit'
alias -- gotop='gotop --mbps'
alias -- gtc='gt continue'
alias -- gtms='gt modify && gt ss'
alias -- gtn='gt create'
alias -- lg='cd ~/Dev/leadgenie'
alias -- ls='lsd -lah'
alias -- m='git switch main'
alias -- pn=pnpm
alias -- pull='git pull'
alias -- push='git push'
alias -- q=clear
alias -- reload='~/dotfiles/rebuild.sh && exec zsh'
alias -- sc='git commit -m '\''squash [skip-ci]'\'''
alias -- sshh='ssh homelab'
alias -- tilt=/opt/homebrew/bin/tilt
alias -- tmux='tmux -2'
alias -- u='cd ~/Dev/une.haus'
alias -- v=nvim
alias -- vim=nvim
alias -- vimdiff='nvim -d'
alias -- x=exit
source "$HOME/.local/share/zsh-packages/syntax-highlighting"/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)
