-- Menus: right-click menus for chats and categories, "+ New category", header "more" button.
local _, Hush = ...

local W, Data, Compat = Hush.Widgets, Hush.Data, Hush.Compat

local Menus = {}
Hush.Menus = Menus

local function dialog(opts)
    return W.Dialog(Hush.Main.frame, opts)
end

-- ---------------------------------------------------------------------------
-- Chat menu
-- ---------------------------------------------------------------------------

-- Extra entries from modules: fn(key, conv) -> item or list of items.
Menus.extraChatItems = {}

function Menus.ChatItems(key)
    local conv = Data.Get(key)
    if not conv then return {} end
    local items = {}

    if conv.kind ~= "group" then
        -- Move to…
        local sub = {}
        local cats = Data.Categories()
        for _, id in ipairs(cats.order) do
            if id ~= "pinned" then
                local cat = cats.byId[id]
                sub[#sub + 1] = {
                    text = cat.name,
                    checked = not conv.request and not conv.pinned and conv.category == id,
                    onClick = function()
                        -- A pinned chat always shows under Pinned, so moving it also unpins (like drag and drop).
                        if conv.pinned then Data.SetPinned(key, false) end
                        Data.Move(key, id)
                    end,
                }
            end
        end
        items[#items + 1] = { text = "Move to", submenu = sub }
        items[#items + 1] = {
            text = conv.pinned and "Unpin" or "Pin",
            onClick = function() Data.SetPinned(key, not conv.pinned) end,
        }
    end

    items[#items + 1] = {
        text = "Mark as read",
        disabled = conv.unread == 0,
        onClick = function() Data.MarkRead(key) end,
    }

    if conv.kind == "whisper" then
        items[#items + 1] = { separator = true }
        items[#items + 1] = {
            text = "Invite to group",
            onClick = function() Compat.InviteToGroup(conv.target) end,
        }
        items[#items + 1] = {
            text = "Guild invite",
            disabled = not Compat.CanGuildInvite() or Hush.Chat.IsGuildMember(conv.target),
            onClick = function() Compat.GuildInvite(conv.target) end,
        }
    end

    for _, fn in ipairs(Menus.extraChatItems) do
        local ok, extra = pcall(fn, key, conv)
        if ok and extra then
            if extra.text or extra.separator then extra = { extra } end
            items[#items + 1] = { separator = true }
            for _, it in ipairs(extra) do items[#items + 1] = it end
        elseif not ok then
            geterrorhandler()(extra)
        end
    end

    items[#items + 1] = { separator = true }
    items[#items + 1] = {
        text = "Delete chat",
        danger = true,
        onClick = function()
            dialog({
                title = "Delete chat",
                text = "Delete the conversation with " .. conv.display .. "? This removes its history.",
                okText = "Delete",
                danger = true,
                onOk = function() Data.Delete(key) end,
            })
        end,
    }
    return items
end

function Menus.OpenChat(key)
    if Hush.List.IsDragging() then return end
    W.OpenMenu(Menus.ChatItems(key))
end

-- ---------------------------------------------------------------------------
-- Category menu
-- ---------------------------------------------------------------------------

function Menus.NewCategory()
    dialog({
        title = "New category",
        input = "",
        okText = "Create",
        onOk = function(name) Data.CreateCategory(name) end,
    })
end

function Menus.OpenCategory(id)
    local cats = Data.Categories()
    local cat = cats.byId[id]
    if not cat then return end
    local items = {}
    if id ~= "pinned" then
        items[#items + 1] = {
            text = "Rename",
            onClick = function()
                dialog({
                    title = "Rename category",
                    input = cat.name,
                    okText = "Rename",
                    onOk = function(name) Data.RenameCategory(id, name) end,
                })
            end,
        }
    end
    items[#items + 1] = { text = "Move up", onClick = function() Data.MoveCategory(id, -1) end }
    items[#items + 1] = { text = "Move down", onClick = function() Data.MoveCategory(id, 1) end }
    items[#items + 1] = {
        text = cat.collapsed and "Expand" or "Collapse",
        onClick = function() Data.SetCategoryCollapsed(id, not cat.collapsed) end,
    }
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "New category", onClick = Menus.NewCategory }
    if not cat.locked then
        items[#items + 1] = {
            text = "Delete category",
            danger = true,
            onClick = function()
                dialog({
                    title = "Delete category",
                    text = "Delete \"" .. cat.name .. "\"? Its chats move to Other.",
                    okText = "Delete",
                    danger = true,
                    onOk = function() Data.DeleteCategory(id) end,
                })
            end,
        }
    end
    W.OpenMenu(items)
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

Hush:RegisterCallback("CONV_CONTEXT", function(_, key) Menus.OpenChat(key) end, "Menus")
Hush:RegisterCallback("CATEGORY_CONTEXT", function(_, id) Menus.OpenCategory(id) end, "Menus")
Hush:RegisterCallback("NEW_CATEGORY", function() Menus.NewCategory() end, "Menus")
Hush:RegisterCallback("WINDOW_HIDDEN", function() W.CloseMenus() end, "Menus")

-- "More" (three dots) button in the header opens the chat menu for the open conversation.
Hush:RegisterCallback("WINDOW_BUILT", function()
    local header = Hush.Main.header
    local more = W.IconButton(header, "more", 24, "More", function()
        local key = Hush.Conversation.Current()
        if key then Menus.OpenChat(key) end
    end, "...")
    more:SetPoint("RIGHT", header.close, "LEFT", -4, 0)
    more:Hide()
    header.more = more
end, "Menus")

Hush:RegisterCallback("CONV_OPENED", function()
    Hush.Main.header.more:Show()
end, "Menus")

Hush:RegisterCallback("CONV_DELETED", function()
    if not Hush.Conversation.Current() then Hush.Main.header.more:Hide() end
end, "Menus")
