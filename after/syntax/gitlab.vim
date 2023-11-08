if filereadable($VIMRUNTIME . '/syntax/markdown.vim')
  source $VIMRUNTIME/syntax/markdown.vim
endif

syntax match Username "@\S*"
syntax match Date "\v\d+\s+\w+\s+ago"
syntax match ChevronDown ""
syntax match ChevronRight ""

highlight link Username GitlabUsername
highlight link Date GitlabDate
highlight link ChevronDown GitlabChevron
highlight link ChevronRight GitlabChevron

let b:current_syntax = "gitlab"
