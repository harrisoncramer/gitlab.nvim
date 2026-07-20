---@meta diagnostics

---@alias BorderEnum "rounded" | "single" | "double" | "solid"

---@class Author
---@field id integer
---@field username string
---@field email string
---@field name string
---@field state string
---@field avatar_url string
---@field web_url string

---@class LinePosition
---@field line_code string
---@field type string

---@class GitlabLineRange
---@field start LinePosition
---@field end LinePosition

---@class NotePosition
---@field base_sha string
---@field start_sha string
---@field head_sha string
---@field position_type string
---@field new_path string?
---@field new_line integer?
---@field old_path string?
---@field old_line integer?
---@field line_range GitlabLineRange?

---@class Note
---@field id integer
---@field type string
---@field body string
---@field attachment string
---@field title string
---@field file_name string
---@field author Author
---@field system boolean
---@field expires_at string?
---@field updated_at string?
---@field created_at string?
---@field noteable_id integer
---@field noteable_type string
---@field commit_id string
---@field position NotePosition
---@field resolvable boolean
---@field resolved boolean
---@field resolved_by Author
---@field resolved_at string?
---@field noteable_iid integer
---@field url string?

---@class UnlinkedNote: Note
---@field position nil

---@class Discussion
---@field id string
---@field individual_note boolean
---@field notes Note[]

---@class UnlinkedDiscussion: Discussion
---@field notes UnlinkedNote[]

---@class DiscussionData
---@field discussions Discussion[]
---@field unlinked_discussions UnlinkedDiscussion[]

---@class EmojiMap: table<string, Emoji>
---@class Emoji
---@field name string
---@field shortname string
---@field moji string
---@field category string

---@class WinbarTable
---@field view_type string
---@field resolvable_discussions integer
---@field resolved_discussions integer
---@field non_resolvable_discussions integer
---@field inline_draft_notes integer
---@field unlinked_draft_notes integer
---@field resolvable_notes integer
---@field resolved_notes integer
---@field non_resolvable_notes integer
---@field help_keymap string
---@field ahead? integer Number of commits local is ahead of remote
---@field behind? integer Number of commits local is behind remote
---@field updated string
---
---@class SignTable
---@field name string
---@field group string
---@field priority number
---@field id number
---@field lnum number
---@field buffer number?

---@class LineRange
---@field start_line integer
---@field end_line integer

---@class DiffviewInfo
---@field modification_type string
---@field file_name string
---Relevant for renamed files only, the name of the file in the previous commit
---@field old_file_name string
---@field current_bufnr integer
---@field opposite_bufnr integer
---@field new_line_from_buf integer
---@field old_line_from_buf integer
---@field new_sha_focused boolean
---@field current_win_id integer

---@class DraftNote
---@field note string
---@field id integer
---@field author_id integer
---@field merge_request_id integer
---@field resolve_discussion boolean
---@field discussion_id string This will always be "" in a draft note
---@field commit_id string This will always be "" in a draft note
---@field line_code string
---@field position NotePosition

---Plugin Settings
---@class GitlabSettings
---@field config_path? string Absolute path to the directory that holds your `.gitlab.nvim` file (see "Connecting to Gitlab")
---@field auth_provider? GitlabAuthProvider
---@field server? ServerSettings
---@field log_path? string Log path for the Go server
---@field debug? DebugSettings Which values to log
---@field attachment_dir? string The local directory for files (see the "summary" section)
---@field reviewer_settings? ReviewerSettings Settings for the reviewer view
---@field connection_settings? ConnectionSettings Settings for the connection to Gitlab
---@field keymaps? Keymaps Keymaps for the plugin
---@field popup? PopupSettings Settings for the popup windows
---@field discussion_tree? DiscussionSettings Settings for the popup windows
---@field emojis? EmojisSettings Settings for emojis
---@field choose_merge_request? ChooseMergeRequestSettings Default settings when choosing a merge request
---@field info? InfoSettings Settings for the "info" or "summary" view
---@field mergeability_checks? MergeabilityChecksSettings Settings for the mergeability checks in the "summary" view
---@field discussion_signs? DiscussionSigns The settings for discussion signs/diagnostics
---@field pipeline? PipelineSettings The settings for the pipeline popup
---@field create_mr? CreateMrSettings The settings when creating an MR
---@field rebase_mr? RebaseMrSettings The settings when rebasing an MR
---@field colors? GitlabColorSettings Colors settings for the plugin
---The following are set by the plugin
---@field root_path? string The root path of the plugin
---@field auth_token? string The personal access token for Gitlab
---@field gitlab_url? string The URL of the Gitlab server

---Function that returns the `token`, `gitlab_url`, and error
---@alias GitlabAuthProvider fun():string?,string?,string?

---@class ServerSettings
---@field port? number The port of the Go server, which runs in the background, if omitted or `nil` the port will be chosen automatically
---@field binary? string The path to the server binary. If omitted or nil, the server will be built
---The following is set by the plugin
---@field binary_provided? boolean

---@class DiscussionSigns: table
---@field enabled? boolean Show diagnostics for gitlab comments in the reviewer
---@field skip_resolved_discussion? boolean Show diagnostics for resolved discussions
---@field severity? vim.diagnostic.Severity
---@field virtual_text? boolean Whether to show the comment text inline as floating virtual text
---@field use_diagnostic_signs? boolean Show diagnostic sign (depending on the `severity` setting) along with the comment icon
---@field priority? number Higher will override LSP warnings, etc
---@field icons? IconsOpts Customize the icons shown with comments or notes
---@field skip_old_revision_discussion? boolean Don't show diagnostics for discussions that were created for earlier MR revisions

---@class CreateMrSettings: table
---@field target? string Default branch to target when creating an MR
---@field template_file? string Default MR template in .gitlab/merge_request_templates
---@field delete_branch? boolean Whether the source branch will be marked for deletion
---@field squash? boolean Whether the commits will be marked for squashing
---@field title_input? TitleInputSettings
---@field fork? ForkSettings

---@class RebaseMrSettings: table
---@field skip_ci? boolean If true, a CI pipeline is not created.
---@field force? boolean If true, MR is rebased even if MR already is rebased.

---@class GitlabColorSettings: table The color definitions for elements in the plugin's UI, e.g., "Comment", "WarningMsg", etc
---@field discussion_tree DiscussionTreeColors Colors for elements in the discussion tree

---@class DiscussionTreeColors
---@field username? string
---@field mention? string
---@field date? string
---@field unlinked? string
---@field expander? string
---@field directory? string
---@field directory_icon? string
---@field file_name? string
---@field resolved? string
---@field unresolved? string
---@field draft? string
---@field draft_mode? string
---@field live_mode? string
---@field sort_method? string

---@class ForkSettings: table
---@field enabled? boolean If making an MR from a fork
---@field forked_project_id? number The Gitlab ID of the project you are merging into. If nil, will be prompted.

---@class TitleInputSettings: table
---@field width? number
---@field border? BorderEnum

---@class PipelineSettings: table
---@field created? string What to show for this pipeline status, by default "",
---@field pending? string What to show for this pipeline status, by default "",
---@field preparing? string What to show for this pipeline status, by default "",
---@field scheduled? string What to show for this pipeline status, by default "",
---@field running? string What to show for this pipeline status, by default "",
---@field canceled? string What to show for this pipeline status, by default "↪",
---@field skipped? string What to show for this pipeline status, by default "↪",
---@field success? string What to show for this pipeline status, by default "✓",
---@field failed? string What to show for this pipeline status, by default "",

---@class IconsOpts: table
---@field comment? string The icon for comments, by default "→|",
---@field range? string The icon for lines in ranged comments, by default " |"

---@class ReviewerSettings: table
---@field diffview? SettingsDiffview Settings for diffview (the dependency)
---@field jump_with_no_diagnostics? boolean Jump to last position in discussion tree if true, otherwise stay in reviewer and show warning.

---@class SettingsDiffview: table
---@field imply_local? boolean If true, will attempt to use --imply_local option when calling |:DiffviewOpen|

---@class ConnectionSettings: table
---@field proxy? string Proxy URL to use when connecting to GitLab. Supports URL schemes: http, https, socks5
---@field insecure? boolean Like curl's --insecure option, ignore bad x509 certificates on connection
---@field remote string The remote, "origin" by default

---@class DebugSettings: table
---@field go_request? boolean Log the requests to Gitlab sent by the Go server
---@field go_response? boolean Log the responses received from Gitlab to the Go server
---@field request? boolean Log the requests to the Go server
---@field response? boolean Log the responses from the Go server

---@class PopupSettings: table
---@field width? string The width of the popup, by default "40%"
---@field height? string The width of the popup, by default "60%"
---@field position? string|table The position of the popup (by default "50%"), or a table specifying horizontal and vertical position separately { row = "90%", col = "100%" }
---@field border? BorderEnum
---@field opacity? number From 0.0 (fully transparent) to 1.0 (fully opaque)
---@field comment? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 },
---@field edit? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field note? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field help? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field pipeline? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field reply? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field squash_message? string The default message when squashing a commit
---@field create_mr? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field summary? table Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 }
---@field temp_registers? string[] List of registers for backing up popup content (see `:h gitlab.nvim.temp-registers`)

---@class ChooseMergeRequestSettings
---@field open_reviewer? boolean Open the reviewer window automatically after switching merge requests

---@class InfoSettings
---@field enabled? boolean
---@field horizontal? boolean Display metadata to the left of the summary rather than underneath
---@field fields? ("author" | "created_at" | "updated_at" | "merge_status" | "draft" | "conflicts" | "assignees" | "reviewers" | "pipeline" | "branch" | "target_branch" | "auto_merge" | "delete_branch" | "squash" | "labels" | "web_url" | "mergeability_checks")[]

---@class MergeabilityChecksSettings
---@field statuses MergeabilityStatuses
---@field checks MergeabilityChecks

---@class MergeabilityStatuses
---@field SUCCESS string|false
---@field CHECKING string|false
---@field FAILED string|false
---@field WARNING string|false
---@field INACTIVE string|false

---@class MergeabilityChecks
---@field CI_MUST_PASS string|false
---@field COMMITS_STATUS string|false
---@field CONFLICT string|false
---@field DISCUSSIONS_NOT_RESOLVED string|false
---@field DRAFT_STATUS string|false
---@field JIRA_ASSOCIATION_MISSING string|false
---@field LOCKED_LFS_FILES string|false
---@field LOCKED_PATHS string|false
---@field MERGE_REQUEST_BLOCKED string|false
---@field MERGE_TIME string|false
---@field NEED_REBASE string|false
---@field NOT_APPROVED string|false
---@field NOT_OPEN string|false
---@field REQUESTED_CHANGES string|false
---@field SECURITY_POLICY_PIPELINE_CHECK string|false
---@field SECURITY_POLICY_VIOLATIONS string|false
---@field STATUS_CHECKS_MUST_PASS string|false
---@field TITLE_REGEX string|false

---@class DiscussionSettings: table
---@field expanders? ExpanderOpts Customize the expander icons in the discussion tree
---@field spinner_chars? string[] Characters for the refresh animation
---@field auto_open? boolean Automatically open when the reviewer is opened
---@field focus_on_open? boolean Automatically focus the discussion tree when it is opened
---@field default_view? string - Show "discussions" or "notes" by default
---@field blacklist? table<string> List of usernames to remove from tree (bots, CI, etc)
---@field sort_by? "latest_reply"|"original_comment" How to sort discussion tree
---@field keep_current_open? boolean If true, current discussion stays open even if it should otherwise be closed when toggling
---@field position? "top"|"right"|"bottom"|"left"
---@field size? string Size of split, default to "20%"
---@field relative? "editor"|"window" Relative position of tree split
---@field resolved? string Symbol to show next to resolved discussions
---@field unresolved? string Symbol to show next to unresolved discussions
---@field unlinked? string Symbol to show next to unlinked comments (i.e., not threads)
---@field draft? string Symbol to show next to draft comments/notes
---@field tree_type? "simple"|"by_file_name" Type of discussion tree - "simple" means just list of discussions, "by_file_name" means file tree with discussions under file
---@field draft_mode? boolean Whether comments are posted as drafts as part of a review
---@field relative_date? boolean Whether to show relative time like "5 days ago" or absolute time like "03/01/2025 at 01:43"
---@field winopts? GitlabDiscussionsWinopts Window-local options for the discussion tree split
---@field winbar? function Custom function to return winbar title, should return a string. Provided with WinbarTable (defined in annotations.lua)

---@class EmojisSettings: table
---@field formatter? function Custom function to modify how emojis are displayed in the picker.
---@field version? string|fun(gitlab_url: string):string The (function that returns the) emoji version used by the Gitlab instance: https://{GITLAB_URL}/-/emojis/{VERSION}/emojis.json.

---@class ExpanderOpts: table<string, string>
---@field expanded? string Icon for expanded discussion thread
---@field collapsed? string Icon for collapsed discussion thread
---@field indentation? string Indentation Icon

---@class GitlabDiscussionsWinopts
---@field number? boolean Show line numbers
---@field relativenumber? boolean Show relative line numbers
---@field breakindent? boolean Every wrapped line will continue visually indented
---@field showbreak? string String to put at the start of lines that have been wrapped

---@class Keymaps
---@field disable_all boolean Disable all mappings created by the plugin
---@field help? string Open a help popup for local keymaps when a relevant view is focused (popup, discussion panel, etc)
---@field global? KeymapsGlobal Global keybindings which will apply everywhere in Neovim
---@field popup? KeymapsPopup Keymaps for the popups (creating a comment, reading the summary, etc)
---@field discussion_tree? KeymapsDiscussionTree Keymaps for the discussion tree pane
---@field reviewer? KeymapsReviewer Keymaps for the reviewer view

---@class KeymapTable: table<string, table<string, string | boolean>>
---@field disable_all? boolean Disable all built-in keymaps

---@class KeymapsPopup: KeymapTable
---@field next_field? string Cycle to the next field. Accepts |count|.
---@field prev_field? string Cycle to the previous field. Accepts |count|.
---@field perform_action? string Once in normal mode, does action (like saving comment or applying description edit, etc)
---@field perform_linewise_action? string Once in normal mode, does the linewise action (see logs for this job, etc)
---@field discard_changes? string Quit the popup discarding changes, the popup content is not saved to the `temp_registers` (see `:h gitlab.nvim.temp-registers`)
---
---@class KeymapsDiscussionTree: KeymapTable
---@field add_emoji? string Add an emoji to the note/comment
---@field delete_emoji? string Remove an emoji from a note/comment
---@field delete_comment? string Delete comment
---@field edit_comment? string Edit comment
---@field reply? string Reply to comment
---@field toggle_resolved? string Toggle the resolved status of the whole discussion
---@field jump_to_file? string Jump to comment location in file
---@field jump_to_reviewer? string Jump to the comment location in the reviewer window
---@field open_in_browser? string Jump to the URL of the current note/discussion
---@field copy_node_url? string Copy the URL of the current node to clipboard
---@field switch_view? string Toggle between the notes and discussions views
---@field toggle_tree_type? string Toggle type of discussion tree - "simple", or "by_file_name"
---@field publish_draft? string Publish the currently focused note/comment
---@field toggle_date_format? string Toggle between date formats: relative (e.g., "5 days ago", "just now", "October 13, 2024" for dates more than a month ago) and absolute (e.g., "03/01/2024 at 11:43")
---@field toggle_draft_mode? string Toggle between draft mode (comments posted as drafts) and live mode (comments are posted immediately)
---@field toggle_sort_method? string Toggle whether discussions are sorted by the "latest_reply", or by "original_comment", see `:h gitlab.nvim.toggle_sort_method`
---@field toggle_node? string Open or close the discussion
---@field toggle_all_discussions? string Open or close separately both resolved and unresolved discussions
---@field toggle_resolved_discussions? string Open or close all resolved discussions
---@field toggle_unresolved_discussions? string Open or close all unresolved discussions
---@field refresh_data? string Refresh the data in the view by hitting Gitlab's APIs again
---@field print_node? string Print the current node (for debugging)
---
---@class KeymapsReviewer: KeymapTable
---@field create_comment? string Create a comment for the lines that the following {motion} moves over. Repeat the key(s) for creating comment for the current line
---@field create_suggestion? string Creates suggestion for the lines that the following {motion} moves over. Repeat the key(s) for creating comment for the current line
---@field move_to_discussion_tree? string Jump to the comment in the discussion tree
---
---@class KeymapsGlobal: KeymapTable
---@field disable_all? boolean Disable all built-in keymaps
---@field add_assignee? string Add an assignee to the merge request
---@field delete_assignee? string Delete an assignee from the merge request
---@field add_label? string Add a label from the merge request
---@field delete_label? string Remove a label from the merge request
---@field add_reviewer? string Add a reviewer to the merge request
---@field delete_reviewer? string Delete a reviewer from the merge request
---@field approve? string Approve MR
---@field revoke? string Revoke MR approval
---@field merge? string Merge the feature branch to the target branch and close MR
---@field set_auto_merge? string Set MR to merge automatically when the pipeline succeeds
---@field rebase? string Rebase the feature branch of the MR on the server and pull the new state
---@field rebase_skip_ci? string Same as `rebase`, but skip the CI pipeline
---@field rebase_force? string Same as `rebase`, but rebase even if MR already is rebased
---@field create_mr? string Create a new MR for currently checked-out feature branch
---@field choose_merge_request? string Chose MR for review (if necessary check out the feature branch)
---@field start_review? string Start review for the currently checked-out branch
---@field reload_review? string Load new MR state from Gitlab and apply new diff refs to the diff view
---@field summary? string Show the editable summary of the MR
---@field copy_mr_url? string Copy the URL of the MR to the system clipboard
---@field open_in_browser? string Open the URL of the MR in the default Internet browser
---@field create_note? string Create a note (comment not linked to a specific line)
---@field pipeline? string Show the pipeline status
---@field toggle_discussions? string Toggle the discussions window
---@field toggle_draft_mode? string Toggle between draft mode (comments posted as drafts) and live mode (comments are posted immediately)
---@field publish_all_drafts? string Publish all draft comments/notes

---@class List The base class for all list objects
---@field new function Creates a new List from a table
---@field map function Mutates a given list
---@field filter function Filters a given list
---@field partition function Partitions a given list into two lists
---@field reduce function Applies a function to reduce the list to a single value
---@field sort function Sorts the list in place based on a comparator function
---@field find function Returns the first element that satisfies the callback
---@field slice function Returns a portion of the list between start and end indices
---@field includes function Returns true if any of the elements can satisfy the callback
---@field values function Returns an iterator over the list's values

---@class PopupOpts The options for customizing popup windows
---@field title string The string to appear on top of the popup
---@field user_settings? table User-defined popup settings
---@field width? number Override default width
---@field height? number Override default height
---@field zindex? number Override default zindex

---@class GitlabDependency Specifications for fetching data from the Go server
---@field endpoint string The Go server endpoint, e.g., "/merge_requests"
---@field key? string The key under which the data is stored in the Go server's response, e.g., "merge_requests"
---@field state string The name under which the data is stored in the plugin state, e.g., "MERGE_REQUESTS"
---@field refresh boolean If true, forces re-fetching the data, if false, only fetches the data if not in state already.
---@field method? string The request method to send to the Go server (default: "GET")
---@field body? fun(opts?):table Function that returns a table that will be passed as the request body to the Go server.

---@class GitlabDependencies
---@field user GitlabDependency
---@field info GitlabDependency
---@field mergeability GitlabDependency
---@field latest_pipeline GitlabDependency
---@field labels GitlabDependency
---@field revisions GitlabDependency
---@field draft_notes GitlabDependency
---@field project_members GitlabDependency
---@field merge_requests GitlabDependency
---@field merge_requests_by_username GitlabDependency
---@field discussion_data GitlabDependency
