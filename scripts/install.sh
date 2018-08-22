#!/bin/bash

DEVFOR_ROOT="$HOME/.devfor"
DEVFOR_USER="$DEVFOR_ROOT/user_config"
DEVFOR_REPO="$DEVFOR_ROOT/.repo"

fancy_echo() {
  # shellcheck disable=SC2039
  local fmt="$1"; shift

  # shellcheck disable=SC2059
  printf "\n$fmt\n" "$@"
}

append_to_file() {
  # shellcheck disable=SC2039
  local file="$1"
  # shellcheck disable=SC2039
  local text="$2"

  if [ "$file" = "$HOME/.zshrc" ]; then
    if [ -w "$HOME/.zshrc.local" ]; then
      file="$HOME/.zshrc.local"
    else
      file="$HOME/.zshrc"
    fi
  elif [ "$file" = "$HOME/.bash_profile" ]; then
    file="$HOME/.bash_profile"
  fi

  if ! grep -qs "^$text$" "$file"; then
    printf "\n%s\n" "$text" >> "$file"
  fi
}

create_zshrc_and_set_it_as_shell_file() {
  if [ ! -f "$HOME/.zshrc" ]; then
    touch "$HOME/.zshrc"
  fi

  shell_file="$HOME/.zshrc"
}

create_bash_profile_and_set_it_as_shell_file() {
  if [ ! -f "$HOME/.bash_profile" ]; then
    touch "$HOME/.bash_profile"
  fi

  shell_file="$HOME/.bash_profile"
}

sync_user_repo() {
  local repo="$1"
  if [ "$repo" = "" ]; then
    fancy_echo "Skip repo configuration!"
  else
    if [ ! -d "$DEVFOR_USER" ]; then
      fancy_echo "Cloning your configuration repo to: $DEVFOR_REPO"
      git clone $repo $DEVFOR_USER
    else
      fancy_echo "Updating your configuration repo to: $DEVFOR_REPO"
      pushd $DEVFOR_USER
      git pull --rebase --stat origin master
      popd
    fi
    echo "$repo" > "$DEVFOR_REPO"
  fi
}

# Sync latest configuration from remote repo
if [ ! -f $DEVFOR_REPO ]; then
  printf "Input git remote repo to restore configuration: "
  read REPO
else
  REPO=$(cat $DEVFOR_REPO)
  fancy_echo "Load saved configuration from: $REPO"
fi
sync_user_repo $REPO

# shellcheck disable=SC2154
trap 'ret=$?; test $ret -ne 0 && printf "failed\n\n" >&2; exit $ret' EXIT

set -e

if [ ! -d "$HOME/.bin/" ]; then
  mkdir "$HOME/.bin"
fi

case "$SHELL" in
  */zsh) :
    create_zshrc_and_set_it_as_shell_file
    ;;
  *)
    create_bash_profile_and_set_it_as_shell_file
    if [ -z "$CI" ]; then
      bold=$(tput bold)
      normal=$(tput sgr0)
      echo "Want to switch your shell from the default ${bold}bash${normal} to ${bold}zsh${normal}?"
      echo "Both work fine for development, and ${bold}zsh${normal} has some extra "
      echo "features for customization and tab completion."
      echo "If you aren't sure or don't care, we recommend ${bold}zsh${normal}."
      echo "Note that you can always switch back to ${bold}bash${normal} if you change your mind."
      echo "Please see the README for instructions."
      echo -n "Press ${bold}y${normal} to switch to zsh, ${bold}n${normal} to keep bash: "
      read -r -n 1 response
      if [ "$response" = "y" ]; then
        fancy_echo "=== Getting ready to change your shell to zsh. Please enter your password to continue. ==="
        echo "=== Note that there won't be visual feedback when you type your password. Type it slowly and press return. ==="
        echo "=== Press control-c to cancel ==="
        create_zshrc_and_set_it_as_shell_file
        chsh -s "$(which zsh)"
      else
        fancy_echo "Shell will not be changed."
      fi
    else
      fancy_echo "CI System detected, will not change shells"
    fi
    ;;
esac

brew_is_installed() {
  brew list -1 | grep -Fqx "$1"
}

tap_is_installed() {
  brew tap -1 | grep -Fqx "$1"
}

gem_install_or_update() {
  if gem list "$1" | grep "^$1 ("; then
    fancy_echo "Updating %s ..." "$1"
    gem update "$@"
  else
    fancy_echo "Installing %s ..." "$1"
    gem install "$@"
  fi
}

app_is_installed() {
  # shellcheck disable=SC2039
  local app_name
  app_name=$(echo "$1" | cut -d'-' -f1)
  find /Applications -iname "$app_name*" -maxdepth 1 | egrep '.*' > /dev/null
}

latest_installed_ruby() {
  find "$HOME/.rubies" -maxdepth 1 -name 'ruby-*' | tail -n1 | egrep -o '\d+\.\d+\.\d+'
}

switch_to_latest_ruby() {
  # shellcheck disable=SC1091
  . /usr/local/share/chruby/chruby.sh
  chruby "ruby-$(latest_installed_ruby)"
}

append_to_file "$shell_file" "alias devfor='bash <(curl -s https://raw.githubusercontent.com/nampdn/devfor/master/mac)'"

# shellcheck disable=SC2016
append_to_file "$shell_file" 'export PATH="$HOME/.bin:$PATH"'

if ! command -v brew >/dev/null; then
  fancy_echo "Installing Homebrew ..."
    curl -fsS \
      'https://raw.githubusercontent.com/Homebrew/install/master/install' | ruby

    # shellcheck disable=SC2016
    append_to_file "$shell_file" 'export PATH="/usr/local/bin:$PATH"'
else
  fancy_echo "Homebrew already installed. Skipping ..."
fi

# Remove brew-cask since it is now installed as part of brew tap caskroom/cask.
# See https://github.com/caskroom/homebrew-cask/releases/tag/v0.60.0
if brew_is_installed 'brew-cask'; then
  brew uninstall --force 'brew-cask'
fi

if tap_is_installed 'caskroom/versions'; then
  brew untap caskroom/versions
fi

fancy_echo "Updating Homebrew..."
brew update

fancy_echo "Verifying the Homebrew installation..."
if brew doctor; then
  fancy_echo "Your Homebrew installation is good to go."
else
  fancy_echo "Your Homebrew installation reported some errors or warnings."
  echo "If the warnings are related to Python, you can ignore them."
  echo "Otherwise, review the Homebrew messages to see if any action is needed."
fi

if brew_is_installed 'cloudfoundry-cli'; then
  brew uninstall --force cloudfoundry-cli
fi

fancy_echo "Installing formulas and casks from the Brewfile ..."
if brew bundle --file="$HOME/.devfor/Brewfile"; then
  fancy_echo "All formulas and casks were installed successfully."
else
  fancy_echo "Some formulas or casks failed to install."
  echo "This is usually due to one of the Mac apps being already installed,"
  echo "in which case, you can ignore these errors."
fi

# shellcheck disable=SC2016
append_to_file "$shell_file" 'eval "$(hub alias -s)"'

fancy_echo 'Checking on Node.js installation...'

if ! brew_is_installed "node"; then
  if command -v n > /dev/null; then
    fancy_echo "We recommend using \`nvm\` and not \`n\`."
    fancy_echo "See https://pages.18f.gov/frontend/#install-npm"
  elif ! command -v nvm > /dev/null; then
    fancy_echo 'Installing nvm and lts Node.js and npm...'
    curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install node --lts
  else
    fancy_echo 'version manager detected.  Skipping...'
  fi
else
  brew bundle --file=- <<EOF
  brew 'node'
EOF
fi

fancy_echo '...Finished Node.js installation checks.'


fancy_echo 'Checking on Python installation...'

if ! brew_is_installed "python3"; then
  brew bundle --file=- <<EOF
  brew 'pyenv'
  brew 'pyenv-virtualenv'
  brew 'pyenv-virtualenvwrapper'
EOF
  # shellcheck disable=SC2016
  append_to_file "$shell_file" 'if which pyenv > /dev/null; then eval "$(pyenv init -)"; fi'
  # shellcheck disable=SC2016
  append_to_file "$shell_file" 'if which pyenv-virtualenv-init > /dev/null; then eval "$(pyenv virtualenv-init -)"; fi'

  # pyenv currently doesn't have a convenience version to use, e.g., "latest",
  # so we check for the latest version against Homebrew instead.
  latest_python_3="$(brew info python3 | egrep -o "3\.\d+\.\d+" | head -1)"

  if ! pyenv versions | ag "$latest_python_3" > /dev/null; then
    pyenv install "$latest_python_3"
    pyenv global "$latest_python_3"
    pyenv rehash
  fi
else
  brew bundle --file=- <<EOF
  brew 'python3'
EOF
fi

if ! brew_is_installed "pyenv-virtualenvwrapper"; then
  if ! pip3 list | ag "virtualenvwrapper" > /dev/null; then
    fancy_echo 'Installing virtualenvwrapper...'
    pip3 install virtualenvwrapper
    append_to_file "$shell_file" 'export VIRTUALENVWRAPPER_PYTHON=/usr/local/bin/python3'
    append_to_file "$shell_file" 'export VIRTUALENVWRAPPER_VIRTUALENV=/usr/local/bin/virtualenv'
    append_to_file "$shell_file" 'source /usr/local/bin/virtualenvwrapper.sh'
  fi
fi

fancy_echo '...Finished Python installation checks.'


fancy_echo 'Checking on Ruby installation...'

append_to_file "$HOME/.gemrc" 'gem: --no-document'

if command -v rbenv >/dev/null || command -v rvm >/dev/null; then
  fancy_echo 'We recommend chruby and ruby-install over RVM or rbenv'
else
  if ! brew_is_installed "chruby"; then
    fancy_echo 'Installing chruby, ruby-install, and the latest Ruby...'

    brew bundle --file=- <<EOF
    brew 'chruby'
    brew 'ruby-install'
EOF

    append_to_file "$shell_file" 'source /usr/local/share/chruby/chruby.sh'
    append_to_file "$shell_file" 'source /usr/local/share/chruby/auto.sh'

    ruby-install ruby

    append_to_file "$shell_file" "chruby ruby-$(latest_installed_ruby)"

    switch_to_latest_ruby
  else
    brew bundle --file=- <<EOF
    brew 'chruby'
    brew 'ruby-install'
EOF
    fancy_echo 'Checking if a newer version of Ruby is available...'
    switch_to_latest_ruby

    ruby-install --latest > /dev/null
    latest_stable_ruby="$(cat < "$HOME/.cache/ruby-install/ruby/stable.txt" | tail -n1)"

    if ! [ "$latest_stable_ruby" = "$(latest_installed_ruby)" ]; then
      fancy_echo "Installing latest stable Ruby version: $latest_stable_ruby"
      ruby-install ruby
    else
      fancy_echo 'You have the latest version of Ruby'
    fi
  fi
fi

fancy_echo 'Updating Rubygems...'
gem update --system

gem_install_or_update 'bundler'

fancy_echo "Configuring Bundler ..."
number_of_cores=$(sysctl -n hw.ncpu)
bundle config --global jobs $((number_of_cores - 1))

fancy_echo '...Finished Ruby installation checks.'

if app_is_installed 'GitKraken'; then
  fancy_echo "It looks like you've already configured your GitKraken SSH keys."
  fancy_echo "If not, you can do it by signing in to the GitKraken app on your Mac."
elif [ ! -f "$HOME/.ssh/id_rsa.pub" ]; then
  open ~/Applications/GitKraken.app
fi

if [ -f "$HOME/.devfor.local" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.devfor.local"
fi

fancy_echo 'All done!'
