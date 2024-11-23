if filereadable($VIMRUNTIME . '/syntax/markdown.vim')
  source $VIMRUNTIME/syntax/markdown.vim
endif

let expanders = '^\s*\%(' . g:gitlab_discussion_tree_expander_open . '\|' . g:gitlab_discussion_tree_expander_closed . '\)'

syntax match GitlabDate "\v\d+\s+\w+\s+ago"

execute 'syntax match GitlabUnresolved "\s' . g:gitlab_discussion_tree_unresolved . '\s\?"'

execute 'syntax match GitlabUnlinked "\s' . g:gitlab_discussion_tree_unlinked . '\s\?"'

execute 'syntax match GitlabResolved "\s' . g:gitlab_discussion_tree_resolved . '\s\?"'

execute 'syntax match GitlabExpander "' . expanders . '"'

execute 'syntax match GitlabDraft "' . g:gitlab_discussion_tree_draft . '"'

execute 'syntax match GitlabUsername "@[a-zA-Z0-9.]\+"'

execute 'syntax match GitlabMention "\%(' . expanders . '\)\@<!@[a-zA-Z0-9.]*"'

let b:current_syntax = 'gitlab'
