-- Centralized keybinding configuration

local M = {}
local catUtils = require("nixCatsUtils")
local helpers = require("myLuaConf.helpers")

-- ============================================================================
-- Global keymaps
-- ============================================================================

function M.setup_global_keymaps()
  vim.keymap.set("n", "<C-f>", "<C-d>zz", { desc = "Scroll Down" })
  vim.keymap.set("n", "<C-b>", "<C-u>zz", { desc = "Scroll Up" })
  vim.keymap.set("n", "n", "nzzzv", { desc = "Next Search Result" })
  vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous Search Result" })

  -- Create a command `:BufOnly` for deleting all but the current buffer
  vim.api.nvim_create_user_command("BufOnly", '%bd|e#|bd#|norm `"', { desc = "Close all other buffers" })

  vim.keymap.set("n", "<leader><leader>[", "<cmd>bprev<CR>", { desc = "Previous buffer" })
  vim.keymap.set("n", "<leader><leader>]", "<cmd>bnext<CR>", { desc = "Next buffer" })
  vim.keymap.set("n", "<leader><leader>l", "<cmd>b#<CR>", { desc = "Last buffer" })
  vim.keymap.set("n", "<leader><leader>d", "<cmd>bdelete<CR>", { desc = "Delete buffer" })
  vim.keymap.set("n", "<leader><leader>o", "<cmd>BufOnly<CR>", { desc = "Close all other buffers" })

  vim.keymap.set("n", "<leader>tw", function()
    vim.wo.wrap = not vim.wo.wrap
  end, { desc = "Toggle word wrap", silent = true })
  vim.keymap.set("n", "<leader>tW", function()
    if vim.bo.formatoptions:find("t") then
      vim.opt_local.formatoptions:remove("t")
    else
      vim.opt_local.formatoptions:append("t")
    end
  end, { desc = "Toggle hard wrap (auto newline at textwidth)", silent = true })
  -- Remap for dealing with word wrap
  vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
  vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

  -- Diagnostic keymaps
  vim.keymap.set("n", "[d", function()
    vim.diagnostic.jump({ count = -1 })
  end, { desc = "Go to previous diagnostic message" })
  vim.keymap.set("n", "]d", function()
    vim.diagnostic.jump({ count = 1 })
  end, { desc = "Go to next diagnostic message" })
  vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
  vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

  -- Copy to/from clipboard
  -- In order to not clobber system-wide clipboard, easy-to-use keymaps instead of
  -- vim.o.clipboard = 'unnamedplus'
  -- Uses OSC52 for copy, in order to ease copying inside ssh+tmux
  -- vim.g.clipboard = {
  --   name = "OSC 52",
  --   copy = {
  --     ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
  --     ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
  --   },
  --   paste = {
  --     ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
  --     ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
  --   },
  -- }
  vim.keymap.set({ "v", "x", "n" }, "<leader>y", '"+y', { noremap = true, silent = true, desc = "Yank to clipboard" })
  vim.keymap.set(
    { "n", "v", "x" },
    "<leader>Y",
    '"+yy',
    { noremap = true, silent = true, desc = "Yank line to clipboard" }
  )
  vim.keymap.set(
    { "n", "v", "x" },
    "<leader>p",
    '"+p',
    { noremap = true, silent = true, desc = "Paste from clipboard" }
  )
  vim.keymap.set(
    "i",
    "<C-p>",
    "<C-r><C-p>+",
    { noremap = true, silent = true, desc = "Paste from clipboard from within insert mode" }
  )

  vim.keymap.set({ "n", "v", "x" }, "<leader>a", "gg0vG$", { noremap = true, silent = true, desc = "Select all" })

  -- Move lines
  -- This is replaced by mini.move
  if not catUtils.enableForCategory("mini", true) and catUtils.enableForCategory("nomini", false) then
    vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Moves Line Down" })
    vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Moves Line Up" })
  end

  -- File operations
  vim.keymap.set("n", "<leader>fw", "<cmd>w<CR>", { desc = "Write file" })
  vim.keymap.set("n", "<leader>fW", "<cmd>w!<CR>", { desc = "Force write file" })
end

-- Sets <Esc> to dismiss notify (if provided) and clear search highlighting
function M.setup_esc_keymap(notify_dismiss_fn)
  if notify_dismiss_fn then
    vim.keymap.set("n", "<Esc>", function()
      notify_dismiss_fn({ silent = true })
      vim.cmd("nohlsearch")
    end, { desc = "Dismiss notify popup and clear search highlight", silent = true })
  else
    vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight", silent = true })
  end
end

-- ============================================================================
-- Which-Key Setup
-- ============================================================================

function M.setup_which_key()
  local wk = require("which-key")

  wk.add({
    { "<leader><leader>", group = "buffer commands" },
    { "<leader><leader>_", hidden = true },
    { "<leader>f", group = "[f]ile" },
    { "<leader>f_", hidden = true },
    { "<leader>g", group = "[g]it" },
    { "<leader>g_", hidden = true },
    { "<leader>m", group = "[m]arkdown" },
    { "<leader>m_", hidden = true },
    { "<leader>s", group = "[s]earch" },
    { "<leader>s_", hidden = true },
    { "<leader>t", group = "[t]oggles" },
    { "<leader>t_", hidden = true },
    { "<leader>w", group = "[w]orkspace" },
    { "<leader>w_", hidden = true },
  })

  -- Hide file explorer keymaps in which-key, as they should be muscle memory, see `oil_lze_keys`
  wk.add({
    { "-", mode = "n", hidden = true },
    { "<leader>-", mode = "n", hidden = true },
  })
end

-- ============================================================================
-- LSP Keymaps (buffer-local)
-- ============================================================================

function M.setup_lsp_keymaps(_, bufnr)
  local nmap = function(keys, func, desc)
    if desc then
      desc = "LSP: " .. desc
    end
    vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
  end

  -- Telescope as default gr* navigation, gR* for native quickfix fallback
  -- Native grn (rename), gra (code action), grx (codelens) are kept as-is
  if catUtils.enableForCategory("general.telescope", true) then
    nmap("grd", function()
      require("telescope.builtin").lsp_definitions()
    end, "[G]oto [D]efinition")
    nmap("grD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
    nmap("grt", function()
      require("telescope.builtin").lsp_type_definitions()
    end, "[G]oto [T]ype definition")
    nmap("grr", function()
      require("telescope.builtin").lsp_references()
    end, "[G]oto [R]eferences")
    nmap("gri", function()
      require("telescope.builtin").lsp_implementations()
    end, "[G]oto [I]mplementation")
    nmap("gO", function()
      require("telescope.builtin").lsp_document_symbols()
    end, "Document symbols")
    nmap("<leader>ws", function()
      require("telescope.builtin").lsp_dynamic_workspace_symbols()
    end, "[W]orkspace [S]ymbols")
    nmap("gRd", vim.lsp.buf.definition, "[G]oto [D]efinition (native)")
    nmap("gRr", vim.lsp.buf.references, "[G]oto [R]eferences (native)")
    nmap("gRi", vim.lsp.buf.implementation, "[G]oto [I]mplementation (native)")
  else
    nmap("grd", vim.lsp.buf.definition, "[G]oto [D]efinition")
  end

  nmap("K", vim.lsp.buf.hover, "Hover Documentation")
  nmap("<C-S>", vim.lsp.buf.signature_help, "Signature Help")
  nmap("<leader>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
  nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
  nmap("<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, "[W]orkspace [L]ist Folders")

  -- Create a command `:LSPFormat` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, "LSPFormat", function(_)
    vim.lsp.buf.format()
  end, { desc = "Format current buffer with LSP" })
  nmap("<leader>fF", vim.lsp.buf.format, "Format current buffer with LSP")

end

-- ============================================================================
-- Plugin-Specific Keymaps
-- ============================================================================

-- Luasnip keymaps
function M.setup_luasnip_keymaps(ls)
  vim.keymap.set({ "i", "s" }, "<M-n>", function()
    if ls.choice_active() then
      ls.change_choice(1)
    end
  end)
end

-- nvim-ufo keymaps for folding
function M.setup_ufo_keymaps()
  vim.keymap.set("n", "zR", require("ufo").openAllFolds)
  vim.keymap.set("n", "zM", require("ufo").closeAllFolds)
  vim.keymap.set("n", "zr", require("ufo").openFoldsExceptKinds)
  vim.keymap.set("n", "zm", require("ufo").closeFoldsWith) -- closeAllFolds == closeFoldsWith(0)
  vim.keymap.set("n", "K", function()
    local winid = require("ufo").peekFoldedLinesUnderCursor()
    if not winid then
      vim.lsp.buf.hover()
    end
  end)
end

-- Gitsigns buffer-local keymaps
function M.setup_gitsigns_keymaps(bufnr)
  local gs = package.loaded.gitsigns

  local function map(mode, l, r, opts)
    opts = opts or {}
    opts.buffer = bufnr
    vim.keymap.set(mode, l, r, opts)
  end

  -- Navigation (repeatable with ; and , via treesitter-textobjects)
  local next_hunk_repeat, prev_hunk_repeat = gs.next_hunk, gs.prev_hunk
  local ok, ts_repeat_move = pcall(require, "nvim-treesitter-textobjects.repeatable_move")
  if ok then
    local gs_move = ts_repeat_move.make_repeatable_move(function(opts)
      if opts.forward then
        gs.next_hunk()
      else
        gs.prev_hunk()
      end
    end)
    next_hunk_repeat = function()
      gs_move({ forward = true })
    end
    prev_hunk_repeat = function()
      gs_move({ forward = false })
    end
  end

  map({ "n", "v" }, "]g", function()
    if vim.wo.diff then
      return "]c"
    end
    vim.schedule(function()
      next_hunk_repeat()
    end)
    return "<Ignore>"
  end, { expr = true, desc = "Jump to next git hunk" })

  map({ "n", "v" }, "[g", function()
    if vim.wo.diff then
      return "[c"
    end
    vim.schedule(function()
      prev_hunk_repeat()
    end)
    return "<Ignore>"
  end, { expr = true, desc = "Jump to previous git hunk" })

  -- Actions
  -- visual mode
  map("v", "<leader>gs", function()
    gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
  end, { desc = "stage git hunk" })
  map("v", "<leader>gr", function()
    gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
  end, { desc = "reset git hunk" })
  -- normal mode
  map("n", "<leader>gs", gs.stage_hunk, { desc = "git stage hunk" })
  map("n", "<leader>gr", gs.reset_hunk, { desc = "git reset hunk" })
  map("n", "<leader>gS", gs.stage_buffer, { desc = "git Stage buffer" })
  map("n", "<leader>gu", gs.undo_stage_hunk, { desc = "undo stage hunk" })
  map("n", "<leader>gR", gs.reset_buffer, { desc = "git Reset buffer" })
  map("n", "<leader>gp", gs.preview_hunk, { desc = "preview git hunk" })
  map("n", "<leader>gb", function()
    gs.blame_line({ full = false })
  end, { desc = "git blame line" })
  map("n", "<leader>gd", gs.diffthis, { desc = "git diff against index" })
  map("n", "<leader>gD", function()
    gs.diffthis("~")
  end, { desc = "git diff against last commit" })

  -- Toggles
  map("n", "<leader>gtb", gs.toggle_current_line_blame, { desc = "toggle git blame line" })
  map("n", "<leader>gtd", gs.toggle_deleted, { desc = "toggle git show deleted" })

  -- Text object
  map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "select git hunk" })
end

-- Telescope lze keys (for lazy loading)
function M.telescope_lze_keys()
  return {
    { "<leader>sM", "<cmd>Telescope notify<CR>", mode = { "n" }, desc = "[S]earch [M]essage" },
    { "<leader>sp", helpers.telescope_live_grep_git_root, mode = { "n" }, desc = "[S]earch git [P]roject root" },
    {
      "<leader>/",
      function()
        require("telescope.builtin").current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
          winblend = 10,
          previewer = false,
        }))
      end,
      mode = { "n" },
      desc = "[/] Fuzzily search in current buffer",
    },
    {
      "<leader>s/",
      function()
        require("telescope.builtin").live_grep({
          grep_open_files = true,
          prompt_title = "Live Grep in Open Files",
        })
      end,
      mode = { "n" },
      desc = "[S]earch [/] in Open Files",
    },
    {
      "<leader><leader>s",
      function()
        return require("telescope.builtin").buffers()
      end,
      mode = { "n" },
      desc = "[ ] Find existing buffers",
    },
    {
      "<leader>s.",
      function()
        return require("telescope.builtin").oldfiles()
      end,
      mode = { "n" },
      desc = '[S]earch Recent Files ("." for repeat)',
    },
    {
      "<leader>sr",
      function()
        return require("telescope.builtin").resume()
      end,
      mode = { "n" },
      desc = "[S]earch [R]esume",
    },
    {
      "<leader>sd",
      function()
        return require("telescope.builtin").diagnostics()
      end,
      mode = { "n" },
      desc = "[S]earch [D]iagnostics",
    },
    {
      "<leader>sg",
      function()
        return require("telescope.builtin").live_grep()
      end,
      mode = { "n" },
      desc = "[S]earch by [G]rep",
    },
    {
      "<leader>sw",
      function()
        return require("telescope.builtin").grep_string()
      end,
      mode = { "n" },
      desc = "[S]earch current [W]ord",
    },
    {
      "<leader>sv",
      function()
        -- Get the selected text
        local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.visualmode() })
        local search_string = table.concat(lines, "\n")

        -- Search with telescope
        require("telescope.builtin").grep_string({ search = search_string })
      end,
      mode = { "x" },
      desc = "[S]earch current [V]isual selection",
    },
    {
      "<leader>ss",
      function()
        return require("telescope.builtin").builtin()
      end,
      mode = { "n" },
      desc = "[S]earch [S]elect Telescope",
    },
    {
      "<leader>sf",
      function()
        return require("telescope.builtin").find_files()
      end,
      mode = { "n" },
      desc = "[S]earch [F]iles",
    },
    {
      "<leader>sk",
      function()
        return require("telescope.builtin").keymaps()
      end,
      mode = { "n" },
      desc = "[S]earch [K]eymaps",
    },
    {
      "<leader>sh",
      function()
        return require("telescope.builtin").help_tags()
      end,
      mode = { "n" },
      desc = "[S]earch [H]elp",
    },
  }
end

-- Returns oil internal keymaps config
function M.get_oil_keymaps()
  return {
    ["g?"] = "actions.show_help",
    ["<CR>"] = "actions.select",
    ["<C-s>"] = "actions.select_vsplit",
    ["<C-h>"] = "actions.select_split",
    ["<C-t>"] = "actions.select_tab",
    ["<C-p>"] = "actions.preview",
    ["<C-c>"] = "actions.close",
    ["<C-l>"] = "actions.refresh",
    ["-"] = "actions.parent",
    ["_"] = "actions.open_cwd",
    ["`"] = "actions.cd",
    ["~"] = "actions.tcd",
    ["gs"] = "actions.change_sort",
    ["gx"] = "actions.open_external",
    ["g."] = "actions.toggle_hidden",
    ["g\\"] = "actions.toggle_trash",
  }
end

-- Oil lze keys (for lazy loading)
function M.oil_lze_keys()
  return {
    { "-", "<cmd>Oil<CR>", mode = "n", desc = "Open Parent Directory" },
    { "<leader>-", "<cmd>Oil .<CR>", mode = "n", desc = "Open nvim root directory" },
  }
end

-- Markdown preview lze keys (for lazy loading)
function M.markdown_lze_keys()
  return {
    { "<leader>mp", "<cmd>MarkdownPreview<CR>", mode = "n", desc = "markdown preview" },
    { "<leader>ms", "<cmd>MarkdownPreviewStop<CR>", mode = "n", desc = "markdown preview stop" },
    { "<leader>mt", "<cmd>MarkdownPreviewToggle<CR>", mode = "n", desc = "markdown preview toggle" },
  }
end

-- Undotree lze keys (for lazy loading)
function M.undotree_lze_keys()
  return {
    { "<leader>u", "<cmd>UndotreeToggle<CR>", mode = "n", desc = "[U]ndo Tree" },
  }
end

-- Lazygit lze keys (for lazy loading)
function M.lazygit_lze_keys()
  return {
    { "<leader>gl", "<cmd>LazyGit<CR>", mode = "n", desc = "[G]it [L]azygit" },
  }
end

-- Conform lze keys (for lazy loading)
function M.conform_lze_keys()
  return {
    { "<leader>ff", "<cmd>Format<cr>", desc = "[F]ormat [F]ile", mode = "n" },
    { "<leader>f", "<cmd>Format<cr>", desc = "[F]ormat selection", mode = "v" },
  }
end

-- DAP lze keys (for lazy loading)
function M.dap_lze_keys()
  return {
    { "<F5>", desc = "Debug: Start/Continue" },
    { "<F1>", desc = "Debug: Step Into" },
    { "<F2>", desc = "Debug: Step Over" },
    { "<F3>", desc = "Debug: Step Out" },
    { "<leader>b", desc = "Debug: Toggle Breakpoint" },
    { "<leader>B", desc = "Debug: Set Breakpoint" },
    { "<F7>", desc = "Debug: See last session result." },
  }
end

-- Spider lze keys (for lazy loading)
function M.spider_lze_keys()
  return {
    {
      "w",
      "<cmd>lua require('spider').motion('w')<CR>",
      mode = { "n", "o", "x" },
      desc = "Next subword (nvim-spider)",
    },
    {
      "e",
      "<cmd>lua require('spider').motion('e')<CR>",
      mode = { "n", "o", "x" },
      desc = "Next end of subword (nvim-spider)",
    },
    {
      "b",
      "<cmd>lua require('spider').motion('b')<CR>",
      mode = { "n", "o", "x" },
      desc = "Previous subword (nvim-spider)",
    },
    {
      "ge",
      "<cmd>lua require('spider').motion('ge')<CR>",
      mode = { "n", "o", "x" },
      desc = "Previous end of subword (nvim-spider)",
    },
    {
      "<C-f>",
      "<Esc>l<cmd>lua require('spider').motion('w')<CR>i",
      mode = "i",
      desc = "Next subword in insert mode (nvim-spider)",
    },
    {
      "<C-b>",
      "<Esc><cmd>lua require('spider').motion('b')<CR>i",
      mode = "i",
      desc = "Previous subword in insert mode (nvim-spider)",
    },
  }
end

-- DAP keymaps setup
function M.setup_dap_keymaps(dap, dapui)
  vim.keymap.set("n", "<F5>", dap.continue, { desc = "Debug: Start/Continue" })
  vim.keymap.set("n", "<F1>", dap.step_into, { desc = "Debug: Step Into" })
  vim.keymap.set("n", "<F2>", dap.step_over, { desc = "Debug: Step Over" })
  vim.keymap.set("n", "<F3>", dap.step_out, { desc = "Debug: Step Out" })
  vim.keymap.set("n", "<leader>b", dap.toggle_breakpoint, { desc = "Debug: Toggle Breakpoint" })
  vim.keymap.set("n", "<leader>B", function()
    dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
  end, { desc = "Debug: Set Breakpoint" })
  vim.keymap.set("n", "<F7>", dapui.toggle, { desc = "Debug: See last session result." })
end

-- Returns treesitter keymaps config
function M.get_treesitter_keymaps()
  local ts_repeat_move = require("nvim-treesitter-textobjects.repeatable_move")
  -- Repeat movements with `;` and `,`
  vim.keymap.set({ "n", "x", "o" }, ";", ts_repeat_move.repeat_last_move)
  vim.keymap.set({ "n", "x", "o" }, ",", ts_repeat_move.repeat_last_move_opposite)

  -- Make builtin f, F, t, T also repeatable with `;` and `,`
  vim.keymap.set({ "n", "x", "o" }, "f", ts_repeat_move.builtin_f_expr, { expr = true })
  vim.keymap.set({ "n", "x", "o" }, "F", ts_repeat_move.builtin_F_expr, { expr = true })
  vim.keymap.set({ "n", "x", "o" }, "t", ts_repeat_move.builtin_t_expr, { expr = true })
  vim.keymap.set({ "n", "x", "o" }, "T", ts_repeat_move.builtin_T_expr, { expr = true })

  return {
    incremental_selection = {
      enable = true,
      keymaps = {
        init_selection = "s",
        node_incremental = "s",
        scope_incremental = "<C-s>",
        node_decremental = "S",
      },
    },
    textobjects = {
      move = {
        enable = true,
        set_jumps = true,
        goto_next_start = {
          ["]m"] = "@function.outer",
          ["]]"] = "@class.outer",
          ["]c"] = "@comment.outer",
          ["]a"] = "@parameter.outer",
          ["]b"] = "@block.outer",
          ["]i"] = "@conditional.outer",
          ["]o"] = "@loop.outer",
          ["]f"] = "@call.outer",
        },
        goto_next_end = {
          ["]M"] = "@function.outer",
          ["]["] = "@class.outer",
          ["]C"] = "@comment.outer",
          ["]A"] = "@parameter.outer",
          ["]B"] = "@block.outer",
          ["]I"] = "@conditional.outer",
          ["]O"] = "@loop.outer",
          ["]F"] = "@call.outer",
        },
        goto_previous_start = {
          ["[m"] = "@function.outer",
          ["[["] = "@class.outer",
          ["[c"] = "@comment.outer",
          ["[a"] = "@parameter.outer",
          ["[b"] = "@block.outer",
          ["[i"] = "@conditional.outer",
          ["[o"] = "@loop.outer",
          ["[f"] = "@call.outer",
        },
        goto_previous_end = {
          ["[M"] = "@function.outer",
          ["[]"] = "@class.outer",
          ["[C"] = "@comment.outer",
          ["[A"] = "@parameter.outer",
          ["[B"] = "@block.outer",
          ["[I"] = "@conditional.outer",
          ["[O"] = "@loop.outer",
          ["[F"] = "@call.outer",
        },
      },
      swap = {
        enable = true,
        swap_next = {
          ["grs"] = "@parameter.inner",
        },
        swap_previous = {
          ["grS"] = "@parameter.inner",
        },
      },
    },
  }
end

-- Returns mini.move mappings config
function M.get_mini_move_mappings()
  return {
    -- Move visual selection in Visual mode
    left = "H",
    right = "L",
    down = "J",
    up = "K",
    -- Move current line in Normal mode
    line_left = "<M-h>",
    line_right = "<M-l>",
    line_down = "<M-k>",
    line_up = "<M-j>",
  }
end

-- Returns mini.ai mappings config
function M.get_mini_ai_keymaps()
  local gen_spec = require("mini.ai").gen_spec
  return {
    custom_textobjects = {
      -- Argument with whitespace included in separator
      a = gen_spec.argument({ separator = "%s*,%s*" }),
      -- Function call with only last part (no dot in name)
      F = gen_spec.function_call({ name_pattern = "[%w_]" }),
      -- Treesitter textobjects
      m = gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
      M = gen_spec.treesitter({ a = "@call.outer", i = "@call.inner" }),
      c = gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
      C = gen_spec.treesitter({ a = "@comment.outer", i = "@comment.inner" }),
      A = gen_spec.treesitter({ a = "@parameter.outer", i = "@parameter.inner" }),
      B = gen_spec.treesitter({ a = "@block.outer", i = "@block.inner" }),
      i = gen_spec.treesitter({ a = "@conditional.outer", i = "@conditional.inner" }),
      l = gen_spec.treesitter({ a = "@loop.outer", i = "@loop.inner" }),
      -- w but with camelCase, snake_case etc. support, see https://github.com/nvim-mini/mini.nvim/discussions/1434
      e = {
        {
          "%f[%a]%l+%d*",
          "%f[%w]%d+",
          "%f[%u]%u%f[%A]%d*",
          "%f[%u]%u%l+%d*",
          "%f[%u]%u%u+%d*",
        },
      },
    },
    mappings = {
      around = "a",
      inside = "i",

      -- NOTE: These override built-in LSP selection mappings on Neovim>=0.12
      around_next = "an",
      inside_next = "in",
      around_last = "al",
      inside_last = "il",

      -- Move cursor to corresponding edge of `a` textobject
      goto_left = "[a",
      goto_right = "]a",
    },
    markdown_textobjects = {
      ["*"] = gen_spec.pair("*", "*", { type = "greedy" }),
      ["_"] = gen_spec.pair("_", "_", { type = "greedy" }),
    },
  }
end

return M
