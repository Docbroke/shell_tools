#!/usr/bin/env bash
#
# fff - fucking fast file-manager.

setup_terminal() {
    # Setup the terminal for the TUI.
    # '\e[?1049h': Use alternative screen buffer.
    # '\e[?7l':    Disable line wrapping.
    # '\e[?25l':   Hide the cursor.
    # '\e[2J':     Clear the screen.
    # '\e[1;Nr':   Limit scrolling to scrolling area.
    #              Also sets cursor to (0,0).
    printf '\e[?1049h\e[?7l\e[?25l\e[2J\e[1;%sr' "$max_items"

    # Hide echoing of user input
    stty -echo
}

reset_terminal() {
    # Reset the terminal to a useable state (undo all changes).
    # '\e[?7h':   Re-enable line wrapping.
    # '\e[?25h':  Unhide the cursor.
    # '\e[2J':    Clear the terminal.
    # '\e[;r':    Set the scroll region to its default value.
    #             Also sets cursor to (0,0).
    # '\e[?1049l: Restore main screen buffer.
    printf '\e[?7h\e[?25h\e[2J\e[;r\e[?1049l'

    # Show user input.
    stty echo
}

clear_screen() {
    # Only clear the scrolling window (dir item list).
    # '\e[%sH':    Move cursor to bottom of scroll area.
    # '\e[9999C':  Move cursor to right edge of the terminal.
    # '\e[1J':     Clear screen to top left corner (from cursor up).
    # '\e[2J':     Clear screen fully (if using tmux) (fixes clear issues).
    # '\e[1;%sr':  Clearing the screen resets the scroll region(?). Re-set it.
    #              Also sets cursor to (0,0).
    printf '\e[%sH\e[9999C\e[1J%b\e[1;%sr' \
           "$((LINES-2))" "${TMUX:+\e[2J}" "$max_items"
}

setup_options() {
    # Some options require some setup.
    # This function is called once on open to parse
    # select options so the operation isn't repeated
    # multiple times in the code.

    # Format for normal files.
    [[ $FFF_FILE_FORMAT == *%f* ]] && {
        file_pre=${FFF_FILE_FORMAT/'%f'*}
        file_post=${FFF_FILE_FORMAT/*'%f'}
    }

    # Format for marked files.
    # Use affixes provided by the user or use defaults, if necessary.
    if [[ $FFF_MARK_FORMAT == *%f* ]]; then
        mark_pre=${FFF_MARK_FORMAT/'%f'*}
        mark_post=${FFF_MARK_FORMAT/*'%f'}
    else
        mark_pre=" "
        mark_post="*"
    fi

    # Find supported 'file' arguments.
    file -I &>/dev/null || : "${file_flags:=biL}"
}

get_term_size() {
    # Get terminal size ('stty' is POSIX and always available).
    # This can't be done reliably across all bash versions in pure bash.
    read -r LINES COLUMNS < <(stty size)

    # Max list items that fit in the scroll area.
    ((max_items=LINES-3))
}

get_ls_colors() {
    # Parse the LS_COLORS variable and declare each file type
    # as a separate variable.
    # Format: ':.ext=0;0:*.jpg=0;0;0:*png=0;0;0;0:'
    [[ $LS_COLORS ]] || {
        FFF_LS_COLORS=0
        return
    }

    # Turn $LS_COLORS into an array.
    IFS=: read -ra ls_cols <<< "$LS_COLORS"

    for ((i=0;i<${#ls_cols[@]};i++)); {
        # Separate patterns from file types.
        [[ ${ls_cols[i]} =~ ^\*[^\.] ]] &&
            ls_patterns+="${ls_cols[i]/=*}|"

        # Prepend 'ls_' to all LS_COLORS items
        # if they aren't types of files (symbolic links, block files etc.)
        [[ ${ls_cols[i]} =~ ^(\*|\.) ]] && {
            ls_cols[i]=${ls_cols[i]#\*}
            ls_cols[i]=ls_${ls_cols[i]#.}
        }
    }

    # Strip non-ascii characters from the string as they're
    # used as a key to color the dir items and variable
    # names in bash must be '[a-zA-z0-9_]'.
    ls_cols=("${ls_cols[@]//[^a-zA-Z0-9=\\;]/_}")

    # Store the patterns in a '|' separated string
    # for use in a REGEX match later.
    ls_patterns=${ls_patterns//\*}
    ls_patterns=${ls_patterns%?}

    # Define the ls_ variables.
    # 'declare' can't be used here as variables are scoped
    # locally. 'declare -g' is not available in 'bash 3'.
    # 'export' is a viable alternative.
    export "${ls_cols[@]}" &>/dev/null
}

 
get_icon() {
    # $1 Absolute path to the file
    # $2 name of the file/directory
    # $3 the extracted extension from the file name

    # Icons for directories
    [[ -d "$1" ]] && {
        case "$2" in
            # English
                '.git'            ) printf -- '???'; return ;;
                'Desktop'         ) printf -- '???'; return ;;
                'Documents'       ) printf -- '???'; return ;;
                'Downloads'       ) printf -- '???'; return ;;
                'Dotfiles'        ) printf -- '???'; return ;;
                'Dropbox'         ) printf -- '???'; return ;;
                'Music'           ) printf -- '???'; return ;;
                'Pictures'        ) printf -- '???'; return ;;
                'Public'          ) printf -- '???'; return ;;
                'Templates'       ) printf -- '???'; return ;;
                'Videos'          ) printf -- '???'; return ;;

                *                 ) printf -- '???'; return ;;
        esac
    }

    # Icons for files with no extension
    [[ "$2" == *"/$3" ]] && { 
        case "$2" in
            '_gvimrc'       | '_vimrc'       |\
            'bspwmrc'       |'cmakelists.txt'|\
            'config'        | 'Makefile'     |\
            'makefile'      | 'sxhkdrc'      |\
            'ini'                            ) printf -- '???'; return ;;

            'authorized_keys'                |\
            'known_hosts'                    |\
            'license'                        |\
            'LICENSE'                        ) printf -- '???'; return ;;

            'gemfile'                        |\
            'Rakefile'                       |\
            'rakefile'                       ) printf -- '???'; return ;;

            'a.out'                          |\
            'configure'                      ) printf -- '???'; return ;;
            
            'dockerfile'                     ) printf -- '???'; return ;;
            'Dockerfile'                     ) printf -- '???'; return ;;
            'dropbox'                        ) printf -- '???'; return ;;
            'exact-match-case-sensitive-2'   ) printf -- 'X2'; return ;;
            'ledger'                         ) printf -- '???'; return ;;
            'node_modules'                   ) printf -- '???'; return ;;
            'playlists'                      ) printf -- '???'; return ;;
            'procfile'                       ) printf -- '???'; return ;;
            'README'                         ) printf -- '???'; return ;;
            '*'                              ) printf -- '???'; return ;;
        esac
    }

    # Icon for files with the name starting with '.' 
    # without an extension
    [[ "$2" == ".$3" ]] && {
        case "$2" in
            '.bash_aliases'                |\
            '.bash_history'                |\
            '.bash_logout'                 |\
            '.bash_profile'                |\
            '.bashprofile'                 |\
            '.bashrc'                      |\
            '.dmrc'                        |\
            '.DS_Store'                    |\
            '.fasd'                        |\
            '.gitattributes'               |\
            '.gitconfig'                   |\
            '.gitignore'                   |\
            '.inputrc'                     |\
            '.jack-settings'               |\
            '.nvidia-settings-rc'          |\
            '.pam_environment'             |\
            '.profile'                     |\
            '.recently-used'               |\
            '.selected_editor'             |\
            '.Xauthority'                  |\
            '.Xdefaults'                   |\
            '.xinitrc'                     |\
            '.xinputrc'                    |\
            '.Xresources'                  |\
            '.zshrc'                       ) printf -- '???'; return ;;

            '.vim'                         |\
            '.viminfo'                     |\
            '.visrc'                       |\
            '.vimrc'                       ) printf -- '???'; return ;;

            '.fehbg'                       ) printf -- '???'; return ;;
            '.gvimrc'                      ) printf -- '???'; return ;;
            '.ncmpcpp'                     ) printf -- '???'; return ;;

            '*'                            ) printf -- '???'; return ;;
        esac
    }

    # Icon for files whose names have an extension
    [[ "$2" == *"."* ]] && {
        # Special files
        case "$2" in
            'cmakelists.txt'                   |\
            'Makefile.ac'                      |\
            'Makefile.in'                      |\
            'mimeapps.list'                    |\
            'user-dirs.dirs'                   ) printf -- '???'; return ;;

            'README.markdown'                  |\
            'README.md'                        |\
            'README.rst'                       |\
            'README.txt'                       ) printf -- '???'; return ;;

            'config.ac'                        |\
            'config.m4'                        |\
            'config.mk'                        ) printf -- '???'; return ;;
            
            'gruntfile.coffee'                 |\
            'gruntfile.js'                     |\
            'gruntfile.ls'                     ) printf -- '???'; return ;;
            
            'package-lock.json'                |\
            'package.json'                     |\
            'webpack.config.js'                ) printf -- '???'; return ;;
            
            'gulpfile.coffee'                  |\
            'gulpfile.js'                      |\
            'gulpfile.ls'                      ) printf -- '???'; return ;;

            'LICENSE.txt'                      |\
            'LICENSE.md'                       ) printf -- '???'; return ;;
            
            
            '.gitlab-ci.yml'                   ) printf -- '???'; return ;;
            'config.ru'                        ) printf -- '???'; return ;;
            'docker-compose.yml'               ) printf -- '???'; return ;;
            'exact-match-case-sensitive-1.txt' ) printf -- 'X1'; return ;;
            'favicon.ico'                      ) printf -- '???'; return ;;
            'mix.lock'                         ) printf -- '???'; return ;;
            'react.jsx'                        ) printf -- '???'; return ;;
        esac

        # extension
        case "$2" in
           *.7z  |*.apk   |\
           *.bz2 |*.cab   |\
           *.cpio|*.deb   |\
           *.gem |*.gz    |\
           *.gzip|*.lha   |\
           *.lzh |*.lzma  |\
           *.rar |*.rpm   |\
           *.tar |*.tgz   |\
           *.xbps|*.xz    |\
           *.zip           ) printf -- '???'; return ;;

           *.bat |*.conf  |\
           *.cvs           |\
           *.htaccess      |\
           *.htpasswd      |\
           *.ini |*.rc    |\
           *.toml|*.yaml  |\
           *.yml           ) printf -- '???'; return ;;

           *.asp |*.awk   |\
           *.bash|*.csh   |\
           *.efi |*.elf   |\
           *.fish|*.ksh   |\
           *.ps1 |*.rom   |\
           *.zsh |*.sh    ) printf -- '???'; return ;;

           *.avi |*.flv   |\
           *.m4v |*.mkv   |\
           *.mov |*.mp4   |\
           *.mpeg|*.mpg   |\
           *.webm          ) printf -- '???'; return ;;


           *.bmp |*.gif   |\
           *.ico |*.jpeg  |\
           *.jpg |*.png   |\
           *.ppt |*.pptx  |\
           *.webp          ) printf -- '???'; return ;;

           *.aup |*.cue   |\
           *.flac|*.m4a   |\
           *.mp3 |*.ogg   |\
           *.wav           ) printf -- '???'; return ;;

           *.c   |*.c++   |\
           *.cc  |*.cp    |\
           *.cpp |*.cxx   |\
           *.h   |*.hpp   ) printf -- '???'; return ;;

           *.docx|*.doc   |\
           *.epub|*.pdf   |\
           *.rtf |*.xls   |\
           *.xlsx          ) printf -- '???'; return ;;

           *.ejs |*.haml  |\
           *.htm |*.html  |\
           *.slim| *.xhtml|\
           *.xml           ) printf -- '???'; return ;;

           *.a   |*.cmake |\
           *.jl  |*.o     |\
           *.so            ) printf -- '???'; return ;;

           *.asm |*.css   |\
           *.less|*.s     ) printf -- '???'; return ;;

           *.db  |*.dump  |\
           *.img |*.iso   |\
           *.sql           ) printf -- '???'; return ;;

           *.f#  |*.fs    |\
           *.fsi |*.fsx   |\
           *.fsscript      ) printf -- '???'; return ;;

           *.markdown      |\
           *.md  |*.mdx   |\
           *.rmd           ) printf -- '???'; return ;;

           *.gemspec       |\
           *.rake|*.rb    ) printf -- '???'; return ;;

           *.dll |*.exe   |\
           *.msi           ) printf -- '???'; return ;;

           *.eex |*.ex    |\
           *.exs |*.leex  ) printf -- '???'; return ;;

           *.class         |\
           *.jar |*.java  ) printf -- '???'; return ;;

           *.mustache      |\
           *.hbs           ) printf -- '???'; return ;;

           *.json          |\
           *.webmanifest   ) printf -- '???'; return ;;

           *.py  |*.pyc   |\
           *.pyd |*.pyo   ) printf -- '???'; return ;;

           *.cbr |*.cbz   ) printf -- '???'; return ;;
           *.clj |*.cljc  ) printf -- '???'; return ;;
           *.cljs|*.edn   ) printf -- '???'; return ;;
           *.hrl |*.erl   ) printf -- '???'; return ;;
           *.hh  |*.hxx   ) printf -- '???'; return ;;
           *.hs  |*.lhs   ) printf -- '???'; return ;;
           *.js  |*.mjs   ) printf -- '???'; return ;;
           *.jsx |*.tsx   ) printf -- '???'; return ;;
           *.key |*.pub   ) printf -- '???'; return ;;
           *.ml  |*.mli   ) printf -- '??'; return ;;
           *.pl  |*.pm    ) printf -- '???'; return ;;
           *.vim |*.vimrc ) printf -- '???'; return ;;
           *.psb |*.psd   ) printf -- '???'; return ;;
           *.rlib|*.rs    ) printf -- '???'; return ;;
           *.sass|*.scss  ) printf -- '???'; return ;;
           *.sln |*.suo   ) printf -- '???'; return ;;

           *.coffee        ) printf -- '???'; return ;;
           *.ai            ) printf -- '???'; return ;;
           *.cs            ) printf -- '???'; return ;;
           *.d             ) printf -- '???'; return ;;
           *.dart          ) printf -- '???'; return ;;
           *.diff          ) printf -- '???'; return ;;
           *.elm           ) printf -- '???'; return ;;
           *.fi            ) printf -- '|'; return ;;
           *.go            ) printf -- '???'; return ;;
           *.log           ) printf -- '???'; return ;;
           *.lua           ) printf -- '???'; return ;;
           *.nix           ) printf -- '???'; return ;;
           *.php           ) printf -- '???'; return ;;
           *.pp            ) printf -- '???'; return ;;
           *.r             ) printf -- '???'; return ;;
           *.rproj         ) printf -- '???'; return ;;
           *.rss           ) printf -- '???'; return ;;
           *.scala         ) printf -- '???'; return ;;
           *.styl          ) printf -- '???'; return ;;
           *.swift         ) printf -- '???'; return ;;
           *.t             ) printf -- '???'; return ;;
           *.tex           ) printf -- '???'; return ;;
           *.ts            ) printf -- '???'; return ;;
           *.twig          ) printf -- '???'; return ;;
           *.vue           ) printf -- '???'; return ;;
           *.xcplayground  ) printf -- '???'; return ;;
           *.xul           ) printf -- '???'; return ;;
        esac
    }


    printf -- '???'; return
}


status_line() {
    # Status_line to print when files are marked for operation.
    local mark_ui="[${#marked_files[@]}] selected (${file_program[*]}) [p] ->"

    # Escape the directory string.
    # Remove all non-printable characters.
    PWD_escaped=${PWD//[^[:print:]]/^[}

    # '\e7':       Save cursor position.
    #              This is more widely supported than '\e[s'.
    # '\e[%sH':    Move cursor to bottom of the terminal.
    # '\e[30;41m': Set foreground and background colors.
    # '%*s':       Insert enough spaces to fill the screen width.
    #              This sets the background color to the whole line
    #              and fixes issues in 'screen' where '\e[K' doesn't work.
    # '\r':        Move cursor back to column 0 (was at EOL due to above).
    # '\e[m':      Reset text formatting.
    # '\e[H\e[K':  Clear line below status_line.
    # '\e8':       Restore cursor position.
    #              This is more widely supported than '\e[u'.
    printf '\e7\e[%sH\e[3%s;4%sm%*s\r%s %s%s\e[m\e[%sH\e[K\e8' \
           "$((LINES-1))" \
           "${FFF_COL5:-0}" \
           "${FFF_COL2:-1}" \
           "$COLUMNS" "" \
           "($((scroll+1))/$((list_total+1)))" \
           "${marked_files[*]:+${mark_ui}}" \
           "${1:-${PWD_escaped:-/}}" \
           "$LINES"
}

read_dir() {
    # Read a directory to an array and sort it directories first.
    local dirs
    local files
    local item_index

    # Set window name.
    printf '\e]2;fff: %s\e'\\ "$PWD"

    # If '$PWD' is '/', unset it to avoid '//'.
    [[ $PWD == / ]] && PWD=

    for item in "$PWD"/*; do
        if [[ -d $item ]]; then
            dirs+=("$item")

            # Find the position of the child directory in the
            # parent directory list.
            [[ $item == "$OLDPWD" ]] &&
                ((previous_index=item_index))
            ((item_index++))
        else
            files+=("$item")
        fi
    done

	## Natural Sorting of Numbers (still hacky) & sort by time in downloads dirs
    IFS=$'\n' 
#    	dirs=($(sort -V <<<"${dirs[*]}"))
#    	files=($(sort -V <<<"${files[*]}"))
	if [[ $PWD == ~/Downloads* ]]; then
		dirs=($(stat -c '%Y=%n' "${dirs[@]}" | sort -nr | cut -d '=' -f2))
		files=($(stat -c '%Y=%n' "${files[@]}" | sort -nr | cut -d '=' -f2))
	fi
    unset IFS
    
    list=("${dirs[@]}" "${files[@]}")

    # Indicate that the directory is empty.
    [[ -z ${list[0]} ]] &&
        list[0]=empty

    ((list_total=${#list[@]}-1))

    # Save the original dir in a second list as a backup.
    cur_list=("${list[@]}")
}

print_line() {
    # Format the list item and print it.
    local file_name=${list[$1]##*/}
    local file_ext=${file_name##*.}
    local format
    local suffix
    local icon

    # If the dir item doesn't exist, end here.
    if [[ -z ${list[$1]} ]]; then
        return

    # Directory.
    elif [[ -d ${list[$1]} ]]; then
        format+=\\e[${di:-1;3${FFF_COL1:-2}}m
        suffix+=/

    # Block special file.
    elif [[ -b ${list[$1]} ]]; then
        format+=\\e[${bd:-40;33;01}m

    # Character special file.
    elif [[ -c ${list[$1]} ]]; then
        format+=\\e[${cd:-40;33;01}m

    # Executable file.
    elif [[ -x ${list[$1]} ]]; then
        format+=\\e[${ex:-01;32}m

    # Symbolic Link (broken).
    elif [[ -h ${list[$1]} && ! -e ${list[$1]} ]]; then
        format+=\\e[${mi:-01;31;7}m

    # Symbolic Link.
    elif [[ -h ${list[$1]} ]]; then
        format+=\\e[${ln:-01;36}m

    # Fifo file.
    elif [[ -p ${list[$1]} ]]; then
        format+=\\e[${pi:-40;33}m

    # Socket file.
    elif [[ -S ${list[$1]} ]]; then
        format+=\\e[${so:-01;35}m

    # Color files that end in a pattern as defined in LS_COLORS.
    # 'BASH_REMATCH' is an array that stores each REGEX match.
    elif [[ $FFF_LS_COLORS == 1 &&
            $ls_patterns &&
            $file_name =~ ($ls_patterns)$ ]]; then
        match=${BASH_REMATCH[0]}
        file_ext=ls_${match//[^a-zA-Z0-9=\\;]/_}
        format+=\\e[${!file_ext:-${fi:-37}}m

    # Color files based on file extension and LS_COLORS.
    # Check if file extension adheres to POSIX naming
    # standard before checking if it's a variable.
    elif [[ $FFF_LS_COLORS == 1 &&
            $file_ext != "$file_name" &&
            $file_ext =~ ^[a-zA-Z0-9_]*$ ]]; then
        file_ext=ls_${file_ext}
        format+=\\e[${!file_ext:-${fi:-37}}m

    else
        format+=\\e[${fi:-37}m
    fi

    # If the list item is under the cursor.
    (($1 == scroll)) &&
        format+="\\e[1;3${FFF_COL4:-6};7m"

    # If the list item is marked for operation.
    [[ ${marked_files[$1]} == "${list[$1]:-null}" ]] && {
        format+=\\e[3${FFF_COL3:-1}m${mark_pre}
        suffix+=${mark_post}
    }

    # Escape the directory string.
    # Remove all non-printable characters.
    file_name=${file_name//[^[:print:]]/^[}

	# Do not print icons if running in console
	if [[ -n $DISPLAY ]]; then
    	printf '\r%b%s\e[m\r' \
        	"${file_pre}${format}$(get_icon "${list[$1]}" "$file_name")""  " \
        	"${file_name}${suffix}${file_post}"
    else
    	printf '\r%b%s\e[m\r' \
        	"${file_pre}${format}" \
        	"${file_name}${suffix}${file_post}"
    fi
}

draw_dir() {
    # Print the max directory items that fit in the scroll area.
    local scroll_start=$scroll
    local scroll_new_pos
    local scroll_end

    # When going up the directory tree, place the cursor on the position
    # of the previous directory.
    ((find_previous == 1)) && {
        ((scroll_start=previous_index))
        ((scroll=scroll_start))

        # Clear the directory history. We're here now.
        find_previous=
    }

    # If current dir is near the top of the list, keep scroll position.
    if ((list_total < max_items || scroll < max_items/2)); then
        ((scroll_start=0))
        ((scroll_end=max_items))
        ((scroll_new_pos=scroll+1))

    # If current dir is near the end of the list, keep scroll position.
    elif ((list_total - scroll < max_items/2)); then
        ((scroll_start=list_total-max_items+1))
        ((scroll_new_pos=max_items-(list_total-scroll)))
        ((scroll_end=list_total+1))

    # If current dir is somewhere in the middle, center scroll position.
    else
        ((scroll_start=scroll-max_items/2))
        ((scroll_end=scroll_start+max_items))
        ((scroll_new_pos=max_items/2+1))
    fi

    # Reset cursor position.
    printf '\e[H'

    for ((i=scroll_start;i<scroll_end;i++)); {
        # Don't print one too many newlines.
        ((i > scroll_start)) &&
            printf '\n'

        print_line "$i"
    }

    # Move the cursor to its new position if it changed.
    # If the variable 'scroll_new_pos' is empty, the cursor
    # is moved to line '0'.
    printf '\e[%sH' "$scroll_new_pos"
    ((y=scroll_new_pos))
}

redraw() {
    # Redraw the current window.
    # If 'full' is passed, re-fetch the directory list.
    [[ $1 == full ]] && {
        read_dir
        scroll=0
    }

    clear_screen
    draw_dir
    status_line
}

mark() {
    # Mark file for operation.
    # If an item is marked in a second directory,
    # clear the marked files.
    [[ $PWD != "$mark_dir" ]] &&
        marked_files=()

    # Don't allow the user to mark the empty directory list item.
    [[ ${list[0]} == empty && -z ${list[1]} ]] &&
        return

    if [[ $1 == all ]]; then
        if ((${#marked_files[@]} != ${#list[@]})); then
            marked_files=("${list[@]}")
            mark_dir=$PWD
        else
            marked_files=()
        fi

        redraw
    else
        if [[ ${marked_files[$1]} == "${list[$1]}" ]]; then
            unset 'marked_files[scroll]'

        else
            marked_files[$1]="${list[$1]}"
            mark_dir=$PWD
        fi

        # Clear line before changing it.
        printf '\e[K'
        print_line "$1"
    fi

	## by sharad, copy last marked file-path to clipboard
	echo ${marked_files[@]} | wl-copy &> /dev/null
	echo ${marked_files[@]} | xclip -i -selection clipboard &> /dev/null

    # Find the program to use.
    case "$2" in
        # ${FFF_KEY_YANK:=y}|${FFF_KEY_YANK_ALL:=Y}) file_program=(cp -iR) ;;
        ${FFF_KEY_YANK:=y}|${FFF_KEY_YANK_ALL:=Y}) 
        	type rsync &> /dev/null && \
        	file_program=(rsync -avP --links --safe-links) || \
        	file_program=(cp -iR)
        	;;
        ${FFF_KEY_MOVE:=m}|${FFF_KEY_MOVE_ALL:=M}) 
        	type rsync &> /dev/null && \
        	file_program=(mv -i)  ;;
        ${FFF_KEY_LINK:=s}|${FFF_KEY_LINK_ALL:=S}) file_program=(ln -s)  ;;

        # These are 'fff' functions.
        ${FFF_KEY_TRASH:=d}|${FFF_KEY_TRASH_ALL:=D})
            file_program=(trash)
        ;;

        ${FFF_KEY_BULK_RENAME:=r}|${FFF_KEY_BULK_RENAME_ALL:=R})
            file_program=(bulk_rename)
        ;;
    esac

    status_line
}

trash() {
    # Remove file(s).
    cmd_line "Remove [${#marked_files[@]}]  items PERMANENTLY ?  [y/n]: " y n

    [[ $cmd_reply != y ]] &&
        return

            rm -r "${@:1:$#-1}"
}

bulk_rename() {
    # Bulk rename files using '$EDITOR'.
    rename_file=${XDG_CACHE_HOME:=${HOME}/.cache}/fff/bulk_rename
    marked_files=("${@:1:$#-1}")

    # Save marked files to a file and open them for editing.
    printf '%s\n' "${marked_files[@]##*/}" > "$rename_file"
    "${EDITOR:-vi}" "$rename_file"

    # Read the renamed files to an array.
    IFS=$'\n' read -d "" -ra changed_files < "$rename_file"

    # If the user deleted a line, stop here.
    ((${#marked_files[@]} != ${#changed_files[@]})) && {
        rm "$rename_file"
        cmd_line "error: Line mismatch in rename file. Doing nothing."
        return
    }

    printf '%s\n%s\n' \
        "# This file will be executed when the editor is closed." \
        "# Clear the file to abort." > "$rename_file"

    # Construct the rename commands.
    for ((i=0;i<${#marked_files[@]};i++)); {
        [[ ${marked_files[i]} != "${PWD}/${changed_files[i]}" ]] && {
            printf 'mv -i -- %q %q\n' \
                "${marked_files[i]}" "${PWD}/${changed_files[i]}"
            local renamed=1
        }
    } >> "$rename_file"

    # Let the user double-check the commands and execute them.
    ((renamed == 1)) && {
        "${EDITOR:-vi}" "$rename_file"

        source "$rename_file"
        rm "$rename_file"
    }

    # Fix terminal settings after '$EDITOR'.
    setup_terminal
}

open() {
    # Open directories and files.
    if [[ -d $1/ ]]; then
        search=
        search_end_early=
        cd "${1:-/}" ||:
        redraw full

    elif [[ -f $1 ]]; then
        clear_screen
        reset_terminal
        opener -d "$1"
        setup_terminal
        redraw full
    fi
}

cmd_line() {
    # Write to the command_line (under status_line).
    cmd_reply=

    # '\e7':     Save cursor position.
    # '\e[?25h': Unhide the cursor.
    # '\e[%sH':  Move cursor to bottom (cmd_line).
    printf '\e7\e[%sH\e[?25h' "$LINES"

    # '\r\e[K': Redraw the read prompt on every keypress.
    #           This is mimicking what happens normally.
    while IFS= read -rsn 1 -p $'\r\e[K'"${1}${cmd_reply}" read_reply; do
        case $read_reply in
            # Backspace.
            $'\177'|$'\b')
                cmd_reply=${cmd_reply%?}

                # Clear tab-completion.
                unset comp c
            ;;

            # Tab.
            $'\t')
                comp_glob="$cmd_reply*"

                # Pass the argument dirs to limit completion to directories.
                [[ $2 == dirs ]] &&
                    comp_glob="$cmd_reply*/"

                # Generate a completion list once.
                [[ -z ${comp[0]} ]] &&
                    IFS=$'\n' read -d "" -ra comp < <(compgen -G "$comp_glob")

                # On each tab press, cycle through the completion list.
                [[ -n ${comp[c]} ]] && {
                    cmd_reply=${comp[c]}
                    ((c=c >= ${#comp[@]}-1 ? 0 : ++c))
                }
            ;;

            # Escape / Custom 'no' value (used as a replacement for '-n 1').
            $'\e'|${3:-null})
                read "${read_flags[@]}" -rsn 2
                cmd_reply=
                break
            ;;

            # Enter/Return.
            "")
                # If there's only one search result and its a directory,
                # enter it on one enter keypress.
                [[ $2 == search && -d ${list[0]} ]] && ((list_total == 0)) && {
                    # '\e[?25l': Hide the cursor.
                    printf '\e[?25l'

                    open "${list[0]}"
                    search_end_early=1

                    # Unset tab completion variables since we're done.
                    unset comp c
                    return
                }

                break
            ;;

            # Custom 'yes' value (used as a replacement for '-n 1').
            ${2:-null})
                cmd_reply=$read_reply
                break
            ;;

            # Replace '~' with '$HOME'.
            "~")
                cmd_reply+=$HOME
            ;;

            # Anything else, add it to read reply.
            *)
                cmd_reply+=$read_reply

                # Clear tab-completion.
                unset comp c
            ;;
        esac

        # Search on keypress if search passed as an argument.
        [[ $2 == search ]] && {
            # '\e[?25l': Hide the cursor.
            printf '\e[?25l'

            # Use a greedy glob to search.
            list=("$PWD"/*"$cmd_reply"*)
            ((list_total=${#list[@]}-1))

            # Draw the search results on screen.
            scroll=0
            redraw

            # '\e[%sH':  Move cursor back to cmd-line.
            # '\e[?25h': Unhide the cursor.
            printf '\e[%sH\e[?25h' "$LINES"
        }
    done

    # Unset tab completion variables since we're done.
    unset comp c

    # '\e[2K':   Clear the entire cmd_line on finish.
    # '\e[?25l': Hide the cursor.
    # '\e8':     Restore cursor position.
    printf '\e[2K\e[?25l\e8'
}

key() {
    # Handle special key presses.
    [[ $1 == $'\e' ]] && {
        read "${read_flags[@]}" -rsn 2

        # Handle a normal escape key press.
        [[ ${1}${REPLY} == $'\e\e['* ]] &&
            read "${read_flags[@]}" -rsn 1 _

        local special_key=${1}${REPLY}
    }

    case ${special_key:-$1} in
        # Open list item.
        # 'C' is what bash sees when the right arrow is pressed
        # ('\e[C' or '\eOC').
        # '' is what bash sees when the enter/return key is pressed.
        ${FFF_KEY_CHILD1:=l}|\
        ${FFF_KEY_CHILD2:=$'\e[C'}|\
        ${FFF_KEY_CHILD3:=""}|\
        ${FFF_KEY_CHILD4:=$'\eOC'})
            open "${list[scroll]}"
        ;;

        o)
        	clear_screen
        	reset_terminal
        	opener "${list[scroll]}"
        	setup_terminal
        	redraw full
		;;

        # Go to the parent directory.
        # 'D' is what bash sees when the left arrow is pressed
        # ('\e[D' or '\eOD').
        # '\177' and '\b' are what bash sometimes sees when the backspace
        # key is pressed.
        ${FFF_KEY_PARENT1:=h}|\
        ${FFF_KEY_PARENT2:=$'\e[D'}|\
        ${FFF_KEY_PARENT3:=$'\177'}|\
        ${FFF_KEY_PARENT4:=$'\b'}|\
        ${FFF_KEY_PARENT5:=$'\eOD'})
            # If a search was done, clear the results and open the current dir.
            if ((search == 1 && search_end_early != 1)); then
                open "$PWD"

            # If '$PWD' is '/', do nothing.
            elif [[ $PWD && $PWD != / ]]; then
                find_previous=1
                open "${PWD%/*}"
            fi
        ;;

        # Scroll down.
        # 'B' is what bash sees when the down arrow is pressed
        # ('\e[B' or '\eOB').
        ${FFF_KEY_SCROLL_DOWN1:=j}|\
        ${FFF_KEY_SCROLL_DOWN2:=$'\e[B'}|\
        ${FFF_KEY_SCROLL_DOWN3:=$'\eOB'})
            ((scroll < list_total)) && {
                ((scroll++))
                ((y < max_items)) && ((y++))

                print_line "$((scroll-1))"
                printf '\n'
                print_line "$scroll"
                status_line
            }
        ;;

        # Scroll up.
        # 'A' is what bash sees when the up arrow is pressed
        # ('\e[A' or '\eOA').
        ${FFF_KEY_SCROLL_UP1:=k}|\
        ${FFF_KEY_SCROLL_UP2:=$'\e[A'}|\
        ${FFF_KEY_SCROLL_UP3:=$'\eOA'})
            # '\e[1L': Insert a line above the cursor.
            # '\e[A':  Move cursor up a line.
            ((scroll > 0)) && {
                ((scroll--))

                print_line "$((scroll+1))"

                if ((y < 2)); then
                    printf '\e[L'
                else
                    printf '\e[A'
                    ((y--))
                fi

                print_line "$scroll"
                status_line
            }
        ;;

        # Go to top.
        ${FFF_KEY_TO_TOP:=g})
            ((scroll != 0)) && {
                scroll=0
                redraw
            }
        ;;

        # Go to bottom.
        ${FFF_KEY_TO_BOTTOM:=G})
            ((scroll != list_total)) && {
                ((scroll=list_total))
                redraw
            }
        ;;

        # Show hidden files.
        ${FFF_KEY_HIDDEN:=.})
            # 'a=a>0?0:++a': Toggle between both values of 'shopt_flags'.
            #                This also works for '3' or more values with
            #                some modification.
            shopt_flags=(u s)
            shopt -"${shopt_flags[((a=${a:=$FFF_HIDDEN}>0?0:++a))]}" dotglob
            redraw full
        ;;

        # Search.
        ${FFF_KEY_SEARCH:=/})
            cmd_line "/" "search"

            # If the search came up empty, redraw the current dir.
            if [[ -z ${list[*]} ]]; then
                list=("${cur_list[@]}")
                ((list_total=${#list[@]}-1))
                redraw
                search=
            else
                search=1
            fi
        ;;

        # Spawn a shell.
        ${FFF_KEY_SHELL:=!})
            reset_terminal

            # Make fff aware of how many times it is nested.
            export FFF_LEVEL
            ((FFF_LEVEL++))

            cd "$PWD" && "$SHELL"
            setup_terminal
            redraw full
        ;;

        # Mark files for operation.
        ${FFF_KEY_YANK:=y}|\
        ${FFF_KEY_MOVE:=m}|\
        ${FFF_KEY_TRASH:=d}|\
        ${FFF_KEY_LINK:=s}|\
        ${FFF_KEY_BULK_RENAME:=r})
            mark "$scroll" "$1"
            ((scroll < list_total)) && {
                ((scroll++))
                ((y < max_items)) && ((y++))

                print_line "$((scroll-1))"
                printf '\n'
                print_line "$scroll"
                status_line
            }
        ;;

        # Mark all files for operation., BULK RENAM ALL changed to 'F2' from B to avoid conflict
        ${FFF_KEY_YANK_ALL:=Y}|\
        ${FFF_KEY_MOVE_ALL:=M}|\
        ${FFF_KEY_TRASH_ALL:=D}|\
        ${FFF_KEY_LINK_ALL:=S}|\
        ${FFF_KEY_BULK_RENAME_ALL:=R})
            mark all "$1"
        ;;

        # Do the file operation.
        ${FFF_KEY_PASTE:=p})
            [[ ${marked_files[*]} ]] && {
                [[ ! -w $PWD ]] && {
                    cmd_line "warn: no write access to dir."
                    return
                }

                # Clear the screen to make room for a prompt if needed.
                clear_screen
                reset_terminal

                stty echo
                printf '\e[1mfff\e[m: %s\n' "Running ${file_program[0]}"
                "${file_program[@]}" "${marked_files[@]}" .
                stty -echo

                marked_files=()
                setup_terminal
                redraw full
            }
        ;;

        # Clear all marked files.
        ${FFF_KEY_CLEAR:=c})
            [[ ${marked_files[*]} ]] && {
                marked_files=()
                redraw
            }
        ;;

        # Rename list item.
        ${FFF_KEY_RENAME:=$'\eOQ'})
            [[ ! -e ${list[scroll]} ]] &&
                return

            cmd_line "rename ${list[scroll]##*/}: "

            [[ $cmd_reply ]] &&
                if [[ -e $cmd_reply ]]; then
                    cmd_line "warn: '$cmd_reply' already exists."

                elif [[ -w ${list[scroll]} ]]; then
                    mv "${list[scroll]}" "${PWD}/${cmd_reply}"
                    redraw full

                else
                    cmd_line "warn: no write access to file."
                fi
        ;;

        # Create new file or directory.
        n)
            cmd_line "create new file/directory: " "dirs"
                if [[ -e $cmd_reply ]]; then
                    cmd_line "warn: '$cmd_reply' already exists."

                elif [[ -w $PWD ]]; then
                    [[ $cmd_reply == */ ]] && \
                    	mkdir -p "${PWD}/${cmd_reply}" || \
                    	: > "$cmd_reply" 
                    redraw full
                else
                    cmd_line "warn: no write access to dir."
                fi
        ;;

        # Show file attributes.
        # ${FFF_KEY_ATTRIBUTES:=x})
        i)
            [[ -e "${list[scroll]}" ]] && {
                clear_screen
                status_line "${list[scroll]}"
                "${FFF_STAT_CMD:-stat}" "${list[scroll]}"
                read -ern 1
                redraw
            }
        ;;

        ## run du/ncdu to get sizes
        u)
            [[ -e "${list[scroll]}" ]] && {
                clear_screen
                reset_terminal
                status_line "${list[scroll]}"
                type ncdu &> /dev/null && ncdu "${list[scroll]}" || du "${list[scroll]}"
                setup_terminal
                redraw
            }
        ;;

        # Toggle executable flag.
        # ${FFF_KEY_EXECUTABLE:=X})
        x)
            [[ -f ${list[scroll]} && -w ${list[scroll]} ]] && {
                if [[ -x ${list[scroll]} ]]; then
                    chmod -x "${list[scroll]}"
                    status_line "Unset executable."
                else
                    chmod +x "${list[scroll]}"
                    status_line "Set executable."
                fi
            }
        ;;

        # Go to dir.
        # ${FFF_KEY_GO_DIR:=:})
        \;)
            cmd_line "go to dir: " "dirs"

            # Let 'cd' know about the current directory.
            cd "$PWD" &>/dev/null ||:

            [[ $cmd_reply ]] &&
                cd "${cmd_reply/\~/$HOME}" &>/dev/null &&
                    open "$PWD"
        ;;
        
        :)
			cmd_line "run command :" "dirs"
            cd "$PWD" &>/dev/null ||:
			[[ $cmd_reply ]] &&
				$cmd_reply &> /dev/null
			open "$PWD"

        ;;
        
        # Go to '$HOME'.
        ${FFF_KEY_GO_HOME:='~'})
            open ~
        ;;

        # Go to previous dir.
        ${FFF_KEY_PREVIOUS:=-})
            open "$OLDPWD"
        ;;

        # Refresh current dir. F5 to refresh
        ${FFF_KEY_REFRESH:=e})
            open "$PWD"
        ;;

        # Directory favourites.
        [1-9])
            favourite="FFF_FAV${1}"
            favourite="${!favourite}"

            [[ $favourite ]] &&
                open "$favourite"
        ;;

        # Quit and store current directory in a file for CD on exit.
        # Don't allow user to redefine 'q' so a bad keybinding doesn't
        # remove the option to quit.
        q)
            : "${FFF_CD_FILE:=${XDG_CACHE_HOME:=${HOME}/.cache}/fff/.fff_d}"

            [[ -w $FFF_CD_FILE ]] &&
                rm "$FFF_CD_FILE"

            [[ ${FFF_CD_ON_EXIT:=1} == 1 ]] &&
                printf '%s\n' "$PWD" > "$FFF_CD_FILE"

            exit
         ;;
         
    esac
}

main() {
    # Handle a directory as the first argument.
    # 'cd' is a cheap way of finding the full path to a directory.
    # It updates the '$PWD' variable on successful execution.
    # It handles relative paths as well as '../../../'.
    #
    # '||:': Do nothing if 'cd' fails. We don't care.
    cd "${2:-$1}" &>/dev/null ||:

    [[ $1 == -v ]] && {
        printf '%s\n' "fff 2.2"
        exit
    }

    [[ $1 == -h ]] && {
        man fff
        exit
    }

    # bash 5 and some versions of bash 4 don't allow SIGWINCH to interrupt
    # a 'read' command and instead wait for it to complete. In this case it
    # causes the window to not redraw on resize until the user has pressed
    # a key (causing the read to finish). This sets a read timeout on the
    # affected versions of bash.
    # NOTE: This shouldn't affect idle performance as the loop doesn't do
    # anything until a key is pressed.
    # SEE: https://github.com/dylanaraps/fff/issues/48
    ((BASH_VERSINFO[0] > 3)) &&
        read_flags=(-t 0.05)

    ((${FFF_LS_COLORS:=1} == 1)) &&
        get_ls_colors

    ((${FFF_HIDDEN:=0} == 1)) &&
        shopt -s dotglob

    # Create the trash and cache directory if they don't exist.
    mkdir -p "${XDG_CACHE_HOME:=${HOME}/.cache}/fff"

    # 'nocaseglob': Glob case insensitively (Used for case insensitive search).
    # 'nullglob':   Don't expand non-matching globs to themselves.
    shopt -s nocaseglob nullglob

    # Trap the exit signal (we need to reset the terminal to a useable state.)
    trap 'reset_terminal' EXIT

    # Trap the window resize signal (handle window resize events).
    trap 'get_term_size; redraw' WINCH

    get_term_size
    setup_options
    setup_terminal
    redraw full

    # Vintage infinite loop.
    for ((;;)); {
        read "${read_flags[@]}" -srn 1 && key "$REPLY"

        # Exit if there is no longer a terminal attached.
        [[ -t 1 ]] || exit 1
    }
}

main "$@"
