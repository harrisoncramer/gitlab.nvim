if filereadable($VIMRUNTIME . '/syntax/markdown.vim')
  source $VIMRUNTIME/syntax/markdown.vim
endif

syntax match Date "\v\d+\s+\w+\s+ago"
highlight link Date GitlabDate

execute 'syntax match Unresolved /\s' . g:gitlab_discussion_tree_unresolved . '\s\?/'
highlight link Unresolved GitlabUnresolved

execute 'syntax match Resolved /\s' . g:gitlab_discussion_tree_resolved . '\s\?/'
highlight link Resolved GitlabResolved

execute 'syntax match GitlabDiscussionOpen /^\s*' . g:gitlab_discussion_tree_expander_open . '/'
highlight link GitlabDiscussionOpen GitlabExpander

execute 'syntax match GitlabDiscussionClosed /^\s*' . g:gitlab_discussion_tree_expander_closed . '/'
highlight link GitlabDiscussionClosed GitlabExpander

execute 'syntax match Draft /' . g:gitlab_discussion_tree_draft . '/'
highlight link Draft GitlabDraft

execute 'syntax match Username "@[a-zA-Z0-9.]\+"'
highlight link Username GitlabUsername

let b:current_syntax = 'gitlab'
