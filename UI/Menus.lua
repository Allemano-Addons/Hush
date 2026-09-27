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

local savedSourceItems -- defined further down (saved messages section)

-- Extra entries from modules: fn(key, conv) -> item or list of items.
Menus.extraChatItems = {}

function Menus.ChatItems(key)
    local conv = Data.Get(key)
    if not conv then return {} end
    -- Other characters: read-only, only "Reply as <you>".
    if Data.IsForeign(key) then
        if conv.kind == "whisper" or conv.kind == "bnet" then
            return { { text = "Reply as " .. Hush.Compat.PlayerName(), onClick = function() Hush.Input.ReplyAs(key) end } }
        end
        return {}
    end
    if conv.kind == "saved" then return savedSourceItems(key, conv) end
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
            -- Known offline (guild/friend): the server would answer with a confusing error.
            text = conv.info.online == false and "Invite to group (offline)" or "Invite to group",
            disabled = conv.info.online == false,
            onClick = function() Compat.InviteToGroup(conv.target) end,
        }
        items[#items + 1] = {
            text = "Guild invite",
            disabled = not Compat.CanGuildInvite() or Hush.Chat.IsGuildMember(conv.target),
            -- Guild invites are protected: run /ginvite through a secure button.
            macro = "/ginvite " .. conv.target,
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
    local items = Menus.ChatItems(key)
    if #items > 0 then W.OpenMenu(items) end
end

-- ---------------------------------------------------------------------------
-- Saved messages: message menu and the menu for a saved source
-- ---------------------------------------------------------------------------

-- Plain text for copying: links become "[Name]", colors are removed.
local function plain(text)
    return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
end

function Menus.CopyText(text)
    dialog({
        title = "Copy text",
        text = "Press Ctrl+C to copy, then Esc.",
        input = plain(text),
        maxLetters = 4000,
        allowEmpty = true,
        okText = "Done",
    })
end

savedSourceItems = function(_, src)
    local items = {}
    if Data.Get(src.convKey) then
        items[#items + 1] = { text = "Open conversation", onClick = function() Hush.List.Select(src.convKey) end }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = {
        text = "Delete all saved",
        danger = true,
        onClick = function()
            dialog({
                title = "Delete saved messages",
                text = ("Delete all %d saved message%s from %s?"):format(#src.msgs, #src.msgs == 1 and "" or "s", src.display),
                okText = "Delete",
                danger = true,
                onOk = function() Hush.Saved.RemoveAll(src.convKey) end,
            })
        end,
    }
    return items
end

-- Right-click on a message in the conversation view.
Hush:RegisterCallback("MESSAGE_CONTEXT", function(_, key, msg)
    local conv = key and Data.Get(key)
    if not conv or not msg then return end
    local items = {}
    local foreign = Data.IsForeign(key) -- another character: copy only
    if not foreign and conv.kind == "saved" then
        items[#items + 1] = { text = "Remove from saved", onClick = function() Hush.Saved.Remove(conv.convKey, msg) end }
    elseif not foreign and msg.d ~= "sys" then
        if msg.saved then
            items[#items + 1] = { text = "Remove from saved", onClick = function() Hush.Saved.Remove(key, msg) end }
        else
            items[#items + 1] = { text = "Save message", onClick = function() Hush.Saved.Add(key, msg) end }
        end
    end
    items[#items + 1] = { text = "Copy text", onClick = function() Menus.CopyText(msg.m) end }
    W.OpenMenu(items)
end, "Menus")

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
