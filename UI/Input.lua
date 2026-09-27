-- Input: message field, send button, quick replies, link insertion and "new message".
local _, Hush = ...

local Theme, W, Data, Compat = Hush.Theme, Hush.Widgets, Hush.Data, Hush.Compat
local S = Theme.size

local Input = {}
Hush.Input = Input

local PAD_X = 20
local QUICK_H = 22
local FOOTER_H = 12 + QUICK_H + 8 + S.inputH + 12
local MAX_QUICK_LABEL = 22

local footer, edit, sendBtn, quickBar, counter
local quickButtons = {}
local compose -- "new message" name field in the header

-- Short display name without realm, used for {name}.
local function shortName(conv)
    return (conv.display:match("^[^%-]+")) or conv.display
end

local function currentConv()
    local key = Hush.Conversation.Current()
    return key and Data.Get(key), key
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

function Input.Send(text)
    local conv = currentConv()
    if not conv then return end
    if conv.kind == "group" and not Hush.Groups.IsActive(conv) then
        Hush:Print("This group has ended, messages can no longer be sent here.")
        return false
    end
    local parts = Data.SplitMessage(text)
    for _, part in ipairs(parts) do
        if not Compat.Send(conv, part) then
            Hush:Print("Can't reach", conv.display, "right now (not on your Battle.net friends list or offline).")
            return false
        end
    end
    return #parts > 0
end

local function sendFromField()
    local text = edit:GetText()
    if strtrim(text) == "" then return end
    if Input.Send(text) ~= false then
        edit:SetText("")
    end
end

local function updateCounter()
    local n = #Data.SplitMessage(edit:GetText())
    counter:SetText(n > 1 and (n .. " messages") or "")
end

-- ---------------------------------------------------------------------------
-- Quick replies
-- ---------------------------------------------------------------------------

local function expand(template)
    local conv = currentConv()
    local name = conv and shortName(conv) or ""
    return (template:gsub("{name}", name))
end

local function layoutQuick()
    if not quickBar then return end
    local replies = Hush.db.quickReplies or {}
    local width = quickBar:GetWidth()
    local x = 0
    for i = 1, 10 do
        local b = quickButtons[i]
        local template = replies[i]
        if template and template ~= "" then
            if not b then
                b = W.Button(quickBar, "", "default")
                b:SetHeight(QUICK_H)
                Theme:SetFont(b.text, "regular", -1)
                b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                b:SetScript("OnClick", function(self)
                    local text = expand(self.template)
                    if IsShiftKeyDown() then
                        Input.Send(text)
                    else
                        edit:SetText(text)
                        edit:SetFocus()
                        edit:SetCursorPosition(#text)
                    end
                end)
                b:HookScript("OnEnter", function(self)
                    W.ShowTooltip(self, expand(self.template) .. "  |cff7c858f(shift-click to send)|r")
                end)
                b:HookScript("OnLeave", function() W.HideTooltip() end)
                quickButtons[i] = b
            end
            b.template = template
            local label = template
            if #label > MAX_QUICK_LABEL then label = label:sub(1, MAX_QUICK_LABEL - 3) .. "..." end
            b.text:SetText(label)
            local bw = b.text:GetStringWidth() + 20
            b:SetWidth(bw)
            b:ClearAllPoints()
            b:SetPoint("LEFT", quickBar, "LEFT", x, 0)
            -- Buttons that don't fit are hidden rather than wrapped.
            b:SetShown(x + bw <= width)
            x = x + bw + 6
        elseif b then
            b:Hide()
        end
    end
end
Input.LayoutQuickReplies = layoutQuick

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function build()
    footer = Hush.Main.footer
    W.Line(footer, "top", "line")

    quickBar = CreateFrame("Frame", nil, footer)
    quickBar:SetPoint("TOPLEFT", PAD_X, -12)
    quickBar:SetPoint("TOPRIGHT", -PAD_X, -12)
    quickBar:SetHeight(QUICK_H)
    quickBar:SetScript("OnSizeChanged", layoutQuick)

    sendBtn = W.Button(footer, "Send", "accent", sendFromField)
    sendBtn:SetHeight(S.inputH)
    sendBtn:SetWidth(72)
    sendBtn:SetPoint("BOTTOMRIGHT", -PAD_X, 12)

    edit = W.EditBox(footer, "Message", S.inputH)
    edit:SetPoint("BOTTOMLEFT", PAD_X, 12)
    edit:SetPoint("BOTTOMRIGHT", sendBtn, "BOTTOMLEFT", -8, 0)
    edit:SetMaxLetters(2000)
    edit:SetScript("OnEnterPressed", sendFromField)
    edit:HookScript("OnTextChanged", updateCounter)

    counter = W.Text(footer, "regular", -2, "textFaint")
    counter:SetPoint("BOTTOMRIGHT", edit, "TOPRIGHT", 0, 3)

    footer:Hide()
end

-- "New message": a name field over the header.
local function buildCompose()
    local header = Hush.Main.header
    compose = CreateFrame("Frame", nil, header)
    compose:SetPoint("TOPLEFT", 0, 0)
    compose:SetPoint("BOTTOMRIGHT", -40, 0)
    compose:SetFrameLevel(header:GetFrameLevel() + 5)
    compose.bg = W.Fill(compose, "window", 1)
    compose.bg:SetAllPoints()

    local label = W.Text(compose, "semibold", 2, "textDim")
    label:SetPoint("LEFT", PAD_X, 0)
    label:SetText("To:")

    local box = W.EditBox(compose, "Character name", S.inputH)
    box:SetPoint("LEFT", label, "RIGHT", 10, 0)
    box:SetWidth(260)
    compose.box = box

    local hint = W.Text(compose, "regular", -1, "textFaint")
    hint:SetPoint("LEFT", box, "RIGHT", 10, 0)
    hint:SetText("Enter to start, Esc to cancel")

    box:SetScript("OnEnterPressed", function(self)
        local name = strtrim(self:GetText() or "")
        self:SetText("")
        compose:Hide()
        if name ~= "" then Input.StartConversation(name) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        compose:Hide()
    end)
    compose:Hide()
end

-- Open (or create) a whisper conversation with a character and focus the input.
function Input.StartConversation(name)
    -- "sigrid" -> "Sigrid" (realm part untouched).
    local char, realm = strsplit("-", name, 2)
    -- "whissel ljud" -> "Whissel Ljud": capitalize every part of the name (surnames on WoW Forever).
    char = char:gsub("(%S)(%S*)", function(first, rest) return strupper(first) .. strlower(rest) end)
    name = Compat.NormalizeName(realm and (char .. "-" .. realm) or char)
    if not name then return end

    -- Reuse an existing conversation regardless of letter case.
    local lname = strlower(name)
    for key, conv in pairs(Data.All()) do
        if conv.kind == "whisper" and strlower(conv.target) == lname then
            Hush.List.Select(key)
            edit:SetFocus()
            return
        end
    end
    local key = Data.WhisperKey(name)
    Data.Ensure(key, { kind = "whisper", target = name, display = name, info = Hush.Chat.LookupInfo(name) })
    Hush.List.Select(key)
    edit:SetFocus()
end

function Input.Focus()
    if edit and footer:IsShown() then edit:SetFocus() end
end

function Input.HasFocus()
    return edit ~= nil and edit:HasFocus()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

Hush:RegisterCallback("WINDOW_BUILT", function()
    build()
    buildCompose()
    -- Shift-clicked links go into the Hush field while it has focus.
    Compat.HookInsertLink(function(link)
        if link and edit:HasFocus() then edit:Insert(link) end
    end)
end, "Input")

-- Unsent text is kept per conversation while switching (for this session).
local drafts = {}
local draftKey

Hush:RegisterCallback("CONV_OPENED", function(_, key, conv)
    if key ~= draftKey then
        if draftKey then
            local text = edit:GetText() or ""
            drafts[draftKey] = text ~= "" and text or nil
        end
        draftKey = key
        edit:SetText(drafts[key] or "")
        drafts[key] = nil
        updateCounter()
    end
    -- Saved messages are read-only: no input.
    if conv.kind == "saved" then
        footer:Hide()
        footer:SetHeight(1)
        if compose then compose:Hide() end
        return
    end
    footer:SetHeight(FOOTER_H)
    footer:Show()
    if conv.kind == "group" then
        local active = Hush.Groups.IsActive(conv)
        edit.placeholder:SetText(active and ("Message " .. (conv.channel == "RAID" and "raid" or "party")) or "This group has ended")
    else
        edit.placeholder:SetText("Message " .. shortName(conv))
    end
    if compose then compose:Hide() end
    layoutQuick()
end, "Input")

Hush:RegisterCallback("CONV_RENAMED", function(_, oldKey, newKey)
    if draftKey == oldKey then draftKey = newKey end
    if drafts[oldKey] then drafts[newKey], drafts[oldKey] = drafts[oldKey], nil end
end, "Input")

-- Conversation.lua closes the view first when the open conversation is deleted.
Hush:RegisterCallback("CONV_DELETED", function()
    if footer and Hush.Conversation.Current() == nil then
        footer:Hide()
        footer:SetHeight(1)
        edit:SetText("")
        draftKey = nil
    end
end, "Input")

Hush:RegisterCallback("NEW_MESSAGE", function()
    if not compose then return end
    compose:Show()
    compose.box:SetFocus()
end, "Input")

Hush:RegisterCallback("QUICK_REPLIES_CHANGED", function() layoutQuick() end, "Input")
