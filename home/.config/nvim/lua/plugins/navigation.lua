return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
        sources = {
          explorer = { hidden = true },
          files = { hidden = true, follow = true },
          grep = { hidden = true, follow = true },
        },
      },
      explorer = { replace_netrw = true },  -- sidebar tree; `nvim <dir>` opens it
      notifier = { enabled = true },
      input = { enabled = true },
    },
    keys = {
      { '<leader>e', function() Snacks.explorer() end, desc = 'Explorer' },
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
  },
}
