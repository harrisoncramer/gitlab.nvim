if filereadable($VIMRUNTIME . '/syntax/markdown.vim')
  source $VIMRUNTIME/syntax/markdown.vim
endif

let expanders = '^\s*\%(' . g:gitlab_discussion_tree_expander_open . '\|' . g:gitlab_discussion_tree_expander_closed . '\)'
let username = '@[a-zA-Z0-9.]\+'

" Covers times like '14 days ago', 'just now', as well as 'October  3, 2024'
let time_ago = '\d\+ \w\+ ago'
let formatted_date = '\w\+ \{1,2}\d\{1,2}, \d\{4}'
let date = '\%(' . time_ago . '\|' . formatted_date . '\|just now\)'

let published = date . ' \%(' . g:gitlab_discussion_tree_resolved . '\|' . g:gitlab_discussion_tree_unresolved . '\|' . g:gitlab_discussion_tree_unlinked . '\)\?'
let state = ' \%(' . published . '\|' . g:gitlab_discussion_tree_draft . '\)'

execute 'syntax match GitlabNoteHeader "' . expanders . username . state . '" contains=GitlabDate,GitlabUnresolved,GitlabUnlinked,GitlabResolved,GitlabExpander,GitlabDraft,GitlabUsername'

execute 'syntax match GitlabDate "' . date . '" contained'
execute 'syntax match GitlabUnresolved "' . g:gitlab_discussion_tree_unresolved . '" contained'
execute 'syntax match GitlabUnlinked "' . g:gitlab_discussion_tree_unlinked . '" contained'
execute 'syntax match GitlabResolved "' . g:gitlab_discussion_tree_resolved . '" contained'
execute 'syntax match GitlabExpander "' . expanders . '" contained'
execute 'syntax match GitlabDraft "' . g:gitlab_discussion_tree_draft . '" contained'
execute 'syntax match GitlabUsername "' . username . '" contained'
execute 'syntax match GitlabMention "' . username . '"'

let b:current_syntax = 'gitlab'
