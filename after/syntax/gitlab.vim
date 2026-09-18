" Don't source the markdown syntax again when reloading this file after Treesitter
" highlighting is started, see `actions/discussions/init.lua`.
if !exists("b:markdown_syntax_loaded") && filereadable($VIMRUNTIME . '/syntax/markdown.vim')
  source $VIMRUNTIME/syntax/markdown.vim
  let b:markdown_syntax_loaded = 1
endif

let username = '@[a-zA-Z0-9._]\+'

" Covers times like '14 days ago', 'just now', as well as 'October  3, 2024', and '02/28/2025 at 00:50'
let time_ago = '\d\+ \w\+ ago'
let formatted_date = '\w\+ \{1,2}\d\{1,2}, \d\{4}'
let absolute_time = '\d\{2}/\d\{2}/\d\{4} at \d\{2}:\d\{2}'
let date = '\%(' . time_ago . '\|' . formatted_date . '\|' . absolute_time . '\|just now\)'

let published = date . ' \%(' . g:gitlab_discussion_tree_resolved . '\|' . g:gitlab_discussion_tree_unresolved . '\|' . g:gitlab_discussion_tree_unlinked . '\)\?'
let state = ' \%(' . published . '\|' . g:gitlab_discussion_tree_draft . '\)'

" Require that the `@` in a GitlabMention is not preceded by a word character, so that
" @doe.com in john@doe.com is not highlighted as a mention.
execute 'syntax match GitlabMention "\(\w\)\@<!' . username . '"'

" The tree draws indentation and the expander icons as virtual text, so a note's header
" starts at the very beginning of the line.
execute 'syntax match GitlabNoteHeader "^' . username . state . '" contains=GitlabDate,GitlabUnresolved,GitlabUnlinked,GitlabResolved,GitlabDraft,GitlabUsername'

execute 'syntax match GitlabDate "' . date . '" contained'
execute 'syntax match GitlabUnresolved "' . g:gitlab_discussion_tree_unresolved . '" contained'
execute 'syntax match GitlabUnlinked "' . g:gitlab_discussion_tree_unlinked . '" contained'
execute 'syntax match GitlabResolved "' . g:gitlab_discussion_tree_resolved . '" contained'
execute 'syntax match GitlabDraft "' . g:gitlab_discussion_tree_draft . '" contained'
execute 'syntax match GitlabUsername "' . username . '" contained'

let b:current_syntax = 'gitlab'
