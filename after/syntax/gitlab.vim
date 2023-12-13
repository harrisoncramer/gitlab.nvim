if filereadable($VIMRUNTIME . '/syntax/markdown.vim')
  source $VIMRUNTIME/syntax/markdown.vim
endif

syntax match Username "@\S*"
syntax match Date "\v\d+\s+\w+\s+ago"
syntax match ChevronDown ""
syntax match ChevronRight ""
syntax match Resolved "✓$"
syntax match Unresolved "-$"

highlight link Username GitlabUsername
highlight link Date GitlabDate
highlight link ChevronDown GitlabChevron
highlight link ChevronRight GitlabChevron
highlight link Resolved GitlabResolved
highlight link Unresolved GitlabUnresolved

let b:current_syntax = "gitlab"
