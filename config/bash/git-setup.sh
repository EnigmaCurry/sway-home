## Git config setup wizard - prompts for user.name/email/default branch if not configured

__git_config_setup() {
    local config_file="$HOME/.config/git/config.local"
    local need_setup=false

    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        need_setup=true
    else
        # Check if user.name and user.email are set
        local user_name user_email
        user_name=$(git config --file "$config_file" user.name 2>/dev/null || true)
        user_email=$(git config --file "$config_file" user.email 2>/dev/null || true)
        if [[ -z "$user_name" ]] || [[ -z "$user_email" ]]; then
            need_setup=true
        fi
    fi

    if [[ "$need_setup" == "true" ]]; then
        echo
        echo "Git user configuration not found. Let's set it up:"
        echo

        ask_no_blank "Enter your git user name (e.g., John Doe)" GIT_USER_NAME
        ask_no_blank "Enter your git email address" GIT_USER_EMAIL
        ask "Enter your preferred default branch name" GIT_DEFAULT_BRANCH "master"

        echo
        echo "You entered:"
        echo "  Name:           $GIT_USER_NAME"
        echo "  Email:          $GIT_USER_EMAIL"
        echo "  Default branch: $GIT_DEFAULT_BRANCH"
        echo

        if confirm "y" "Save this configuration to $config_file"; then
            mkdir -p "$(dirname "$config_file")"
            git config --file "$config_file" user.name "$GIT_USER_NAME"
            git config --file "$config_file" user.email "$GIT_USER_EMAIL"
            git config --file "$config_file" init.defaultBranch "$GIT_DEFAULT_BRANCH"
            echo "Git configuration saved to $config_file"
        else
            echo "Git configuration skipped. You can set it manually later:"
            echo "  git config --file $config_file user.name \"Your Name\""
            echo "  git config --file $config_file user.email \"your@email.com\""
            echo "  git config --file $config_file init.defaultBranch master"
        fi
        echo
    fi
}

__git_config_setup
