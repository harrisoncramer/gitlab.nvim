if filereadable($VIMRUNTIME . '/syntax/markdown.vim')
  source $VIMRUNTIME/syntax/markdown.vim
endif

execute 'syntax match GitlabMention "\(\w\)\@<!@[a-zA-Z0-9._]\+"'

let b:current_syntax = 'gitlab'
