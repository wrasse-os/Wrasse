function fish_prompt --description 'Full working directory prompt'
    set -l suffix '>'
    if functions -q fish_is_root_user; and fish_is_root_user
        set suffix '#'
    end
    set -l dir (string replace -r "^$HOME(/|\$)" '~$1' -- $PWD)
    echo -n -s (set_color $fish_color_cwd) $dir (set_color normal) $suffix ' '
end
