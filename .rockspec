rockspec_format = '3.0'
package = 'gitlab.nvim'
version = 'scm-1'

test_dependencies = {
  'lua >= 5.1',
  'plenary.nvim',
  'nui.nvim',
  'diffview.nvim'
}

source = {
  url = 'git://github.com/harrisoncramer/' .. package,
}

build = {
  type = 'builtin',
}
