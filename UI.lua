local _, I = ...
-- Built from the client's own templates (verified in the Forever UI source)
-- so the ledger matches Forever's Inspect window: metal frame, portrait,
-- bottom tabs, red panel buttons, coin icons.
local W,H=690,432
local CHECK_HEIGHT=56
-- Every tab starts directly under the headline figures.
local CONTENT_TOP=-118
local RATING_BAR_X,RATING_BAR_WIDTH=140,W-164
local RATING_BAR_INSET=3
local DIRECTORY_ROWS=8
-- Drawn larger than the game's default panels: the small fonts are hard to
-- read at 100%. /irs scale overrides this; the window still fits the screen.
I.DEFAULT_SCALE=1.2
local WHITE,GREY,GOLD,GREEN,RED={1,1,1},{.5,.5,.5},{1,.82,0},{.1,1,.1},{1,.2,.15}
-- One color per I.RISK_LEVELS entry, lowest first.
local RISK_COLORS={GREEN,GOLD,{1,.5,.1},RED}
local MISSING="--"
local TABS={"Ledger","History","Characters"}
-- Section context makes the long statistic names redundant in the ledger.
local SHORT={daily="Earned per day",posted="Auctions posted",purchases="Auctions won",largestSale="Largest sale",largestBid="Largest bid"}
-- Ledger categories, one shown at a time: name, statistic keys, tooltip note.
-- Professions has no fixed keys because its rows follow the character's ranks.
local CATEGORIES={
    {"Recorded income",{"looted","quests","vendors","auctions","daily"}},
    {"Spending",{"travel","postage","barber","respec"},"Tracked categories; not all expenses."},
    {"Auction activity",{"posted","purchases","largestSale","largestBid"}},
    {"Professions"},
    {"Activity",I.activityKeys},
}
local ledgerCategory=1
local w,ui
local function fit(frame,width,height)
    local scale=I.db and I.db.scale or I.DEFAULT_SCALE
    if frame then frame:SetScale(math.min(scale,(UIParent:GetWidth()-24)/width,(UIParent:GetHeight()-24)/height)) end
end
function I.FitWindows()
    -- The tabs hang below the frame and the portrait rises above it.
    fit(w,W,(w and w:GetHeight() or H)+40);fit(I.reportWindow,560,420)
end
local function text(parent,font,x,y,width,height,justify,color)
    local f=parent:CreateFontString(nil,"OVERLAY",font)
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);f:SetSize(width,height)
    f:SetJustifyH(justify or "LEFT");f:SetJustifyV("MIDDLE");f:SetWordWrap(false)
    if color then f:SetTextColor(unpack(color)) end
    return f
end
local function fill(parent,x,y,width,height,r,g,b,a)
    local t=parent:CreateTexture(nil,"BORDER")
    t:SetColorTexture(r,g,b,a);t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);t:SetSize(width,height)
    return t
end
local function button(parent,label,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,22);b:SetText(label);b:SetScript("OnClick",fn)
    return b
end
local function heading(parent,title,x,y,width)
    local f=text(parent,"GameFontNormal",x,y,width,16)
    f:SetText(title);fill(parent,x,y-17,width,1,1,.82,0,.25)
    return f
end
-- Blizzard money style: real coin icons, empty denominations omitted.
function I.coins(n)
    if n==nil then return MISSING end
    n=math.floor(n)
    local letters=type(GetCVarBool)=="function" and GetCVarBool("colorblindMode")
    local parts={}
    for index,unit in ipairs({{10000,"Gold","g"},{100,"Silver","s"},{1,"Copper","c"}}) do
        local amount=math.floor(n/unit[1]);if index>1 then amount=amount%100 end
        if amount>0 or (index==3 and #parts==0) then
            local shown=index==1 and I.quantity(amount) or tostring(amount)
            parts[#parts+1]=shown..(letters and unit[3] or "|TInterface\\MoneyFrame\\UI-"..unit[2].."Icon:0:0:2:0|t")
        end
    end
    return table.concat(parts," ")
end
-- Missing is shown the way the game's own statistics pane shows it, never as zero.
local function show(f,snapshot,key)
    local entry=snapshot and snapshot.values and snapshot.values[key]
    if entry and entry.number~=nil and I.byKey[key][4] then f:SetText(I.coins(entry.number))
    elseif entry then f:SetText(I.value(snapshot,key))
    else f:SetText(MISSING) end
    f:SetTextColor(unpack(entry and WHITE or GREY))
end
local function classColor(class)
    if type(class)~="string" or class=="" or type(RAID_CLASS_COLORS)~="table" then return nil end
    local token
    for _,names in ipairs({LOCALIZED_CLASS_NAMES_MALE,LOCALIZED_CLASS_NAMES_FEMALE}) do
        if type(names)=="table" then for key,name in pairs(names) do if name==class then token=key end end end
    end
    local c=RAID_CLASS_COLORS[token or class:upper():gsub("%s","")]
    return c and {c.r,c.g,c.b}
end
local function identity(s)
    local parts={"Level "..tostring(s.level or "?").." "..I.text(s.class)}
    if s.guild and s.guild~="" then parts[#parts+1]="<"..I.text(s.guild)..">" end
    return table.concat(parts,"  ·  ")
end
local function timestamp(at,short)
    return type(at)=="number" and date(short and "%b %d, %H:%M" or "%b %d, %Y · %H:%M:%S",at) or MISSING
end
local function ago(at)
    local minutes=math.max(0,math.floor((GetServerTime()-at)/60))
    if minutes<1 then return "just now" elseif minutes<60 then return minutes.."m ago"
    elseif minutes<2880 then return math.floor(minutes/60).."h ago" end
    return math.floor(minutes/1440).."d ago"
end
local function hideTooltip(self)
    if GameTooltip and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
end
function I.sourceLine(snapshot)
    local status=I.sourceStatus(snapshot)
    if not status.supported or (not snapshot and (not status.selfAPI or not status.comparisonAPI)) then
        return "WARNING: Blizzard statistics API unavailable or unverified · hover for details"
    elseif not status.definitionsChecked then
        return "WARNING: client build differs from IRS definitions · hover for details"
    end
    return "Source: Blizzard statistics API · accuracy unverified · -- = not reported (not zero)"
end
function I.sourceColor(snapshot)
    local status=I.sourceStatus(snapshot)
    return status.warning and RED or GREY
end
local function explainSource(self)
    if not GameTooltip then return end
    local status=I.sourceStatus(I.snapshot)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText("Data source and verification")
    GameTooltip:AddLine(I.DATA_SOURCE_NOTICE,1,1,1,true)
    GameTooltip:AddLine("Client: "..status.client.." · definitions: "..status.definitions,.8,.8,.8,true)
    if status.reason then GameTooltip:AddLine("WARNING: "..status.reason,1,.2,.15,true)
    else GameTooltip:AddLine("Statistic IDs and labels checked for this build. Live values are not independently verified.",.1,1,.1,true) end
    GameTooltip:AddLine(I.DATA_SOURCE_VERIFY,1,.82,0,true)
    GameTooltip:AddLine(I.DISCLAIMER,1,.82,0,true);GameTooltip:Show()
end
local function explain(self)
    local key=self.key
    if not key or not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(I.byKey[key][3])
    local entry=I.snapshot and I.snapshot.values[key]
    GameTooltip:AddLine(entry and (entry.number~=nil and "Reported by WoW at capture time." or "Display only: this format could not be converted safely.") or I.reason(I.snapshot,key),1,1,1,true)
    if key=="acquired" or key=="looted" or key=="quests" or key=="vendors" or key=="auctions" then
        GameTooltip:AddLine(I.INCOME_SOURCES,1,1,1,true)
        if key=="acquired" then GameTooltip:AddLine(I.INCOME_TOTAL_NOTE,.8,.85,.9,true) end
        GameTooltip:AddLine(I.INCOME_TRANSFERS,1,1,1,true)
        GameTooltip:AddLine(I.INCOME_DISCLAIMER,1,.82,0,true)
    end
    if I.byKey[key][5] then GameTooltip:AddLine("Highest rank recorded; the profession may since have been unlearned.",.8,.8,.8,true) end
    if self.note then GameTooltip:AddLine(self.note,.8,.85,.9,true) end
    GameTooltip:Show()
end
local function explainWallet(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(ui.walletTitle:GetText())
    GameTooltip:AddLine(I.snapshot and not I.snapshot.own and "Not visible for other players." or "Shown for your own characters.",1,1,1,true)
    GameTooltip:Show()
end
-- One striped statistic line: gold label, white value, hover for its source.
local function line(parent,x,y,width,index,valueWidth)
    local r=CreateFrame("Frame",nil,parent);r:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);r:SetSize(width,15)
    if index%2==1 then fill(r,0,0,width,15,1,1,1,.05) end
    valueWidth=valueWidth or 100
    r.name=text(r,"GameFontNormalSmall",4,0,width-valueWidth-8,15)
    r.value=text(r,"GameFontHighlightSmall",width-valueWidth-4,0,valueWidth,15,"RIGHT")
    r:EnableMouse(true);r:SetScript("OnEnter",explain);r:SetScript("OnLeave",hideTooltip)
    return r
end
-- Lays statistic rows in two equal columns, filling the left one first.
-- parent: frame; count: number of rows; y: top of the first row. Returns the rows.
local function grid(parent,count,y)
    local rows,perColumn={},math.ceil(count/2)
    for n=1,count do
        local column=n>perColumn and 1 or 0
        local slot=n-column*perColumn
        rows[n]=line(parent,14+column*335,y-(slot-1)*15,325,slot)
    end
    return rows
end
local function makeReport()
    if I.reportWindow then return I.reportWindow end
    local f=CreateFrame("Frame","ForeverIRSReportWindow",UIParent,"ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(f);f:SetTitle("Copy report")
    f:SetSize(560,420);f:SetPoint("CENTER");f:SetFrameStrata("FULLSCREEN_DIALOG");f:SetToplevel(true)
    f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag("LeftButton");f:SetClampedToScreen(true)
    f:SetScript("OnDragStart",function()f:StartMoving()end);f:SetScript("OnDragStop",function()f:StopMovingOrSizing()end)
    if f.CloseButton then f.CloseButton:SetScript("OnClick",function()f:Hide()end) end
    text(f,"GameFontHighlightSmall",14,-30,530,24):SetText("Select all, then copy. Nothing is posted to chat.")
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",f,"TOPLEFT",14,-68);scroll:SetSize(506,320)
    local edit=CreateFrame("EditBox",nil,scroll)
    edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal);edit:SetSize(506,800)
    edit:SetScript("OnEscapePressed",function()f:Hide()end)
    scroll:SetScrollChild(edit)
    button(f,"Close",96,function()f:Hide()end):SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-6,4)
    tinsert(UISpecialFrames,"ForeverIRSReportWindow")
    f.edit=edit;f:Hide();I.reportWindow=f;return f
end
local function openReport()
    local f=makeReport();I.FitWindows();f:Show();f.edit:SetText(I.report(I.snapshot));f.edit:SetFocus();f.edit:HighlightText()
end
function I.RefreshAge()
    if not ui then return end
    ui.age:SetTextColor(unpack(I.pending and GOLD or WHITE))
    if I.directoryMode then ui.age:SetText("Local history");return end
    if I.pending then
        local remaining=I.pending.queuedUntil and math.ceil(I.pending.queuedUntil-GetTime()) or 0
        ui.age:SetText(remaining>0 and "Loading in "..remaining.."s…" or "Loading statistics…")
        return
    end
    local s=I.snapshot
    ui.age:SetText(s and ("Captured "..ago(s.at)) or "No snapshot")
end
local function renderHistory()
    local h=ui.history;local s=I.snapshot;local all=s and I.history(s.guid) or {}
    local entry=s and I.db.characters[s.guid]
    local pages=math.max(1,math.ceil(#all/9))
    I.historyPage=math.max(0,math.min(I.historyPage or 0,pages-1))
    h.caption:SetText("Local snapshots  ·  "..#all.." / 20 saved  ·  first seen "..(entry and timestamp(entry.firstSeen,true) or MISSING)
        .."  ·  client "..(s and I.text(s.build) or I.build()))
    for index,row in ipairs(h.rows) do
        local position=#all-(I.historyPage*9+index-1);local snap=all[position]
        if snap then
            row.time:SetText(timestamp(snap.at,true))
            for _,key in ipairs({"peak","total"}) do
                local value=I.numeric(snap,key=="total" and "acquired" or key)
                row[key]:SetText(I.coins(value));row[key]:SetTextColor(unpack(value~=nil and WHITE or GREY))
            end
            local previous=all[position-1]
            local a,b=I.numeric(snap,"acquired"),I.numeric(previous,"acquired")
            local delta=previous and previous.build==snap.build and a and b and a>=b and a-b or nil
            row.delta:SetText(delta and "+ "..I.coins(delta) or MISSING);row.delta:SetTextColor(unpack(delta and GREEN or GREY))
            row.frame:Show()
        else row.frame:Hide() end
    end
    h.page:SetText("Page "..(I.historyPage+1).." / "..pages)
    h.previous:SetEnabled(I.historyPage>0);h.next:SetEnabled(I.historyPage<pages-1)
end
local function renderDirectory()
    local d=ui.directory;local rows,total=I.directoryRows(I.directoryQuery)
    local pages=math.max(1,math.ceil(#rows/DIRECTORY_ROWS))
    I.directoryPage=math.max(0,math.min(I.directoryPage or 0,pages-1))
    d.caption:SetText(#rows.." / "..total.." characters")
    local sort=I.db.directorySort
    for key,header in pairs(d.headers) do
        local active=sort.key==key
        header:SetNormalFontObject(active and GameFontNormalSmall or GameFontHighlightSmall)
        header.arrow:SetShown(active)
        if active then header.arrow:SetTexCoord(0,1,sort.descending and 1 or 0,sort.descending and 0 or 1) end
    end
    for index,row in ipairs(d.rows) do
        local entry=rows[I.directoryPage*DIRECTORY_ROWS+index]
        row.guid=entry and entry.guid or nil
        if entry then
            local s=entry.snapshot
            row.name:SetText(I.text(s.name)..(s.own and " (you)" or ""));row.name:SetTextColor(unpack(classColor(s.class) or WHITE))
            row.detail:SetText(I.text(s.class)..(s.guild and s.guild~="" and "  ·  <"..I.text(s.guild)..">" or ""))
            row.level:SetText(s.level and I.quantity(s.level) or MISSING)
            row.peak:SetText(I.coins(entry.peak));row.peak:SetTextColor(unpack(entry.peak~=nil and WHITE or GREY))
            row.acquired:SetText(I.coins(entry.acquired));row.acquired:SetTextColor(unpack(entry.acquired~=nil and WHITE or GREY))
            row.lastSeen:SetText(timestamp(entry.lastSeen,true))
            row.count:SetText(tostring(entry.count));row:Show()
        else row:Hide() end
    end
    d.empty:SetText(total==0 and "No saved characters yet. Use My character or inspect a nearby player to save a capture."
        or "No saved characters match this search.")
    d.empty:SetShown(#rows==0)
    d.page:SetText("Page "..(I.directoryPage+1).." / "..pages)
    d.previous:SetEnabled(I.directoryPage>0);d.next:SetEnabled(I.directoryPage<pages-1)
end
local function makeDirectory()
    local d=CreateFrame("Frame",nil,w);d:SetPoint("TOPLEFT",w,"TOPLEFT",0,0);d:SetSize(W,H)
    d.rows={};d.headers={};ui.directory=d;I.directoryPanel=d
    d.search=CreateFrame("EditBox",nil,d,"SearchBoxTemplate")
    d.search:SetSize(240,20);d.search:SetPoint("TOPLEFT",d,"TOPLEFT",22,-70)
    d.search:SetAutoFocus(false);d.search:SetMaxLetters(100);d.search:SetText(I.directoryQuery or "")
    if d.search.Instructions then d.search.Instructions:SetText("Name, guild or class") end
    -- Hooked so the template keeps its instructions text and clear button.
    d.search:HookScript("OnTextChanged",function(self)
        I.directoryQuery=self:GetText();I.directoryPage=0;renderDirectory()
    end)
    d.caption=text(d,"GameFontHighlightSmall",W-230,-70,214,20,"RIGHT")
    local columns={{"name","Character",14,220},{"level","Level",234,44},{"peak","Peak gold",278,130},
        {"acquired","Acquired",408,130},{"lastSeen","Last seen",538,88},{"count","Saves",626,48}}
    for _,def in ipairs(columns) do
        local key=def[1]
        local b=CreateFrame("Button",nil,d,"ColumnDisplayButtonShortTemplate")
        b:SetPoint("TOPLEFT",d,"TOPLEFT",def[3],-96);b:SetSize(def[4],19);b:SetText(def[2])
        b:SetScript("OnClick",function()I.sortDirectory(key);renderDirectory()end)
        b.arrow=b:CreateTexture(nil,"OVERLAY");b.arrow:SetAtlas("auctionhouse-ui-sortarrow",true)
        b.arrow:SetPoint("RIGHT",b,"RIGHT",-6,0);b.arrow:Hide()
        d.headers[key]=b
    end
    for index=1,DIRECTORY_ROWS do
        local row=CreateFrame("Button",nil,d)
        row:SetPoint("TOPLEFT",d,"TOPLEFT",14,-118-(index-1)*27);row:SetSize(W-30,27)
        if index%2==1 then fill(row,0,0,W-30,27,1,1,1,.05) end
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
        row:SetScript("OnClick",function(self)if self.guid then I.OpenSaved(self.guid)end end)
        row.name=text(row,"GameFontHighlight",6,0,210,15)
        row.detail=text(row,"GameFontDisableSmall",6,-14,210,12)
        row.level=text(row,"GameFontHighlightSmall",220,0,44,27,"CENTER")
        row.peak=text(row,"GameFontHighlightSmall",264,0,124,27,"RIGHT")
        row.acquired=text(row,"GameFontHighlightSmall",394,0,124,27,"RIGHT")
        row.lastSeen=text(row,"GameFontHighlightSmall",524,0,82,27,"RIGHT",{.8,.8,.8})
        row.count=text(row,"GameFontHighlightSmall",612,0,42,27,"RIGHT")
        d.rows[index]=row
    end
    d.empty=text(d,"GameFontDisable",40,-190,W-80,50,"CENTER");d.empty:SetWordWrap(true)
    d.previous=button(d,"Previous",84,function()I.directoryPage=(I.directoryPage or 0)-1;renderDirectory()end)
    d.previous:SetPoint("TOPLEFT",d,"TOPLEFT",14,-338)
    d.page=text(d,"GameFontHighlightSmall",100,-338,96,22,"CENTER")
    d.next=button(d,"Next",84,function()I.directoryPage=(I.directoryPage or 0)+1;renderDirectory()end)
    d.next:SetPoint("TOPLEFT",d,"TOPLEFT",198,-338)
    text(d,"GameFontDisableSmall",300,-338,W-316,22,"RIGHT"):SetText("20 snapshots kept per character  ·  saved locally")
    d:SetScript("OnHide",function()d.search:ClearFocus()end)
end
local function selectTab(index)
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    if index==3 then I.OpenDirectory();return end
    if I.directoryMode then
        -- The directory hint no longer applies once a ledger is back on screen.
        I.status=I.snapshot and (I.snapshot.available.." / "..#I.fields.." counters available") or ""
    end
    I.directoryMode=false;I.historyMode=index==2
    if index==2 then I.historyPage=0 end
    I.Render()
end
function I.Render()
    if not ui then return end
    local directory=I.directoryMode==true
    local check=I.verificationView()
    local showError=not directory and check.tone=="error"
    local offset=showError and CHECK_HEIGHT or 0
    if w:GetHeight()~=H+offset then
        w:SetHeight(H+offset);I.FitWindows()
    end
    ui.ledger:SetPoint("TOPLEFT",w,"TOPLEFT",0,-offset)
    ui.ledger:SetShown(not directory);ui.directory:SetShown(directory)
    ui.verification:SetShown(showError)
    ui.copyButton:SetShown(not directory)
    PanelTemplates_SetTab(w,directory and 3 or I.historyMode and 2 or 1)
    ui.status:SetText(I.text(I.status or ""));ui.auto:SetChecked(I.db.autoInspect);I.RefreshAge()
    ui.source:SetText(I.sourceLine(not directory and I.snapshot or nil))
    ui.source:SetTextColor(unpack(I.sourceColor(not directory and I.snapshot or nil)))
    if directory then
        ui.name:SetText("Saved characters");ui.name:SetTextColor(unpack(WHITE))
        ui.identity:SetText("Click a column heading to sort; click it again to reverse.")
        renderDirectory();return
    end
    ui.verification.title:SetText(check.title)
    ui.verification.detail:SetText(check.detail)
    local s=I.snapshot;local subject=s or I.subjectInfo
    ui.name:SetText(subject and I.text(subject.name) or "Character ledger")
    ui.name:SetTextColor(unpack(subject and classColor(subject.class) or WHITE))
    ui.identity:SetText(subject and identity(subject) or "Select a nearby player or open your own statistics.")
    ui.walletTitle:SetText(I.savedView and "Wallet at capture" or "Current wallet")
    show(ui.cards.acquired,s,"acquired");show(ui.cards.peak,s,"peak")
    local wallet=s and s.own and s.wallet
    ui.cards.wallet:SetText(wallet and I.coins(wallet) or MISSING);ui.cards.wallet:SetTextColor(unpack(wallet and WHITE or GREY))
    for _,rows in ipairs(ui.groups) do for key,f in pairs(rows) do show(f,s,key) end end
    local a=I.assess(s);local band=ui.activityBand
    band.title:SetText(a.title);band.title:SetTextColor(unpack(a.known>0 and WHITE or GREY))
    band.summary:SetText(a.summary)
    band.coverage:SetText(a.known.." / "..a.total.." readable")
    local r=I.rating(s);local riskColor=r.level and RISK_COLORS[r.level] or GREY
    ui.ratingValue:SetText(r.risk or "Not rated");ui.ratingValue:SetTextColor(unpack(riskColor))
    ui.ratingDetail:SetText(r.percent and (r.percent.."% unexplained: "..I.coins(r.unexplained).." of "..I.coins(r.received).." is not covered by recorded income.") or r.reason)
    ui.ratingDetail:SetTextColor(unpack(r.percent and WHITE or GREY))
    ui.bar:SetVertexColor(unpack(riskColor))
    ui.bar:SetWidth(math.max(.001,(RATING_BAR_WIDTH-2*RATING_BAR_INSET)*(r.percent or 0)/100));ui.bar:SetShown((r.percent or 0)>0)
    for n,label in ipairs(ui.riskLabels) do label:SetTextColor(unpack(n==r.level and RISK_COLORS[n] or GREY)) end
    for n,p in ipairs(I.professions(s)) do
        local row=ui.ledgerProfessions[n];row.key=p.key
        row.name:SetText(p.label..(p.highest and "*" or ""));show(row.value,s,p.key)
    end
    ui.body:SetShown(not I.historyMode)
    ui.history:SetShown(I.historyMode==true)
    if I.historyMode then renderHistory() end
end
local function makeLedger()
    local ledger=CreateFrame("Frame",nil,w);ledger:SetPoint("TOPLEFT",w,"TOPLEFT",0,0);ledger:SetSize(W,H);ui.ledger=ledger
    -- Headline figures, on every tab. Their caveats live in the tooltips.
    fill(ledger,10,-64,W-20,46,0,0,0,.3)
    for n,def in ipairs({{"acquired","Recorded gold acquired","Blizzard's statistic; not a full ledger."},
        {"peak","Most gold ever held","Historical high, not today's wallet."},{"wallet","Current wallet"}}) do
        local x=14+(n-1)*225
        local title=text(ledger,"GameFontNormalSmall",x,-68,210,12);title:SetText(def[2])
        ui.cards[def[1]]=text(ledger,"GameFontHighlightLarge",x,-82,210,22)
        if def[1]=="wallet" then ui.walletTitle=title end
        if n>1 then fill(ledger,x-8,-68,1,38,1,1,1,.1) end
        local hit=CreateFrame("Frame",nil,ledger);hit:SetPoint("TOPLEFT",ledger,"TOPLEFT",x,-66);hit:SetSize(210,42)
        hit.key=def[1]~="wallet" and def[1] or nil;hit.note=def[3]
        hit:EnableMouse(true);hit:SetScript("OnEnter",hit.key and explain or explainWallet);hit:SetScript("OnLeave",hideTooltip)
    end
    -- Ledger tab: the risk factor, then one category of figures at a time.
    ui.body=CreateFrame("Frame",nil,ledger);ui.body:SetPoint("TOPLEFT",ledger,"TOPLEFT",0,CONTENT_TOP);ui.body:SetSize(W,H)
    local body=ui.body
    -- A scale for the player to weigh, shown beside the figures behind it.
    local rating=CreateFrame("Frame",nil,body);rating:SetPoint("TOPLEFT",body,"TOPLEFT",10,0);rating:SetSize(W-20,82)
    text(rating,"GameFontNormal",4,-2,130,16):SetText("Risk factor")
    ui.ratingValue=text(rating,"GameFontHighlightLarge",4,-18,130,24)
    ui.ratingValue:SetFont(STANDARD_TEXT_FONT,20,"OUTLINE")
    -- An opaque inset track and the game's textured border keep the full
    -- extent visible even when the fill is nearly empty.
    local barFrame=CreateFrame("Frame",nil,rating,"BackdropTemplate")
    barFrame:SetPoint("TOPLEFT",rating,"TOPLEFT",RATING_BAR_X,-4);barFrame:SetSize(RATING_BAR_WIDTH,16)
    barFrame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=false,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    barFrame:SetBackdropColor(.08,.08,.08,1);barFrame:SetBackdropBorderColor(.75,.75,.75,1)
    -- Dim bands and labels keep the whole scale in view at every reading.
    local trackWidth=RATING_BAR_WIDTH-2*RATING_BAR_INSET
    ui.riskLabels={}
    for n,def in ipairs(I.RISK_LEVELS) do
        local nextLevel=I.RISK_LEVELS[n+1]
        local x,width=trackWidth*def[2]/100,trackWidth*((nextLevel and nextLevel[2] or 100)-def[2])/100
        local c=RISK_COLORS[n]
        fill(barFrame,RATING_BAR_INSET+x,-RATING_BAR_INSET,width,16-2*RATING_BAR_INSET,c[1],c[2],c[3],.2)
        ui.riskLabels[n]=text(rating,"GameFontHighlightSmall",RATING_BAR_X+RATING_BAR_INSET+x,-22,width,14,"CENTER")
        ui.riskLabels[n]:SetText(def[1])
    end
    ui.bar=barFrame:CreateTexture(nil,"ARTWORK");ui.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ui.bar:SetPoint("TOPLEFT",barFrame,"TOPLEFT",RATING_BAR_INSET,-RATING_BAR_INSET);ui.bar:SetSize(.001,16-2*RATING_BAR_INSET)
    ui.ratingDetail=text(rating,"GameFontHighlightSmall",4,-46,W-28,14)
    text(rating,"GameFontNormalSmall",4,-62,W-28,14):SetText(I.RATING_LINE)
    rating:EnableMouse(true)
    rating:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        local r=I.rating(I.snapshot)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText("Risk factor")
        if r.percent then
            GameTooltip:AddLine(r.risk.." · "..r.percent.."% unexplained gold",1,1,1,true)
            GameTooltip:AddLine("Peak gold: "..I.coins(r.peak),.8,.85,.9,true)
            GameTooltip:AddLine("Total acquired: "..I.coins(r.acquired),.8,.85,.9,true)
            GameTooltip:AddLine("Itemized income: "..I.coins(r.itemized),.8,.85,.9,true)
        end
        GameTooltip:AddLine(I.RISK_SCALE,1,1,1,true)
        GameTooltip:AddLine(I.RATING_METHOD,1,1,1,true)
        GameTooltip:AddLine(I.RATING_NOTE,1,.82,0,true)
        GameTooltip:AddLine(I.INCOME_TOTAL_NOTE,.8,.85,.9,true)
        GameTooltip:AddLine(I.INCOME_TRANSFERS,1,1,1,true)
        GameTooltip:AddLine("Missing data and counter resets can also affect the difference.",.8,.8,.8,true)
        GameTooltip:Show()
    end)
    rating:SetScript("OnLeave",hideTooltip)
    local function showCategory()
        for n,panel in ipairs(ui.categories) do panel:SetShown(n==ledgerCategory) end
    end
    ui.categories={}
    for n,category in ipairs(CATEGORIES) do
        local panel=CreateFrame("Frame",nil,body);panel:SetPoint("TOPLEFT",body,"TOPLEFT",0,-92);panel:SetSize(W,150)
        local keys=category[2]
        local rows=grid(panel,keys and #keys or #I.professionKeys,-30)
        if keys then
            local values={}
            for index,key in ipairs(keys) do
                local r=rows[index];r.key=key;r.note=category[3]
                r.name:SetText(SHORT[key] or I.byKey[key][3]);values[key]=r.value
            end
            ui.groups[#ui.groups+1]=values
        else
            ui.ledgerProfessions=rows
            text(panel,"GameFontDisableSmall",W-198,-4,184,16,"RIGHT"):SetText("* highest rank recorded")
        end
        ui.categories[n]=panel
    end
    -- Factual activity summary under the Activity rows; hover for the returned counters.
    local band=CreateFrame("Frame",nil,ui.categories[#CATEGORIES]);band:SetPoint("TOPLEFT",ui.categories[#CATEGORIES],"TOPLEFT",14,-110);band:SetSize(W-28,32)
    ui.activityBand=band
    band.title=text(band,"GameFontHighlightSmall",4,0,300,14)
    band.coverage=text(band,"GameFontDisableSmall",W-186,0,150,14,"RIGHT")
    band.summary=text(band,"GameFontHighlightSmall",4,-16,W-40,14)
    band:EnableMouse(true)
    band:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        local a=I.assess(I.snapshot)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(a.title)
        GameTooltip:AddLine(a.coverage,.8,.8,.8,true);GameTooltip:AddLine(I.ASSESSMENT_NOTE,1,1,1,true)
        for _,entry in ipairs(a.evidence) do GameTooltip:AddLine(entry,.8,.85,.9,true) end
        GameTooltip:Show()
    end)
    band:SetScript("OnLeave",hideTooltip)
    showCategory()
    local picker=CreateFrame("DropdownButton",nil,body,"WowStyle1DropdownTemplate")
    picker:SetPoint("TOPLEFT",body,"TOPLEFT",14,-92);picker:SetWidth(200)
    picker:SetupMenu(function(_,root)
        for n,category in ipairs(CATEGORIES) do
            root:CreateRadio(category[1],function()return ledgerCategory==n end,function()ledgerCategory=n;showCategory()end)
        end
    end)
    -- History tab.
    ui.history=CreateFrame("Frame",nil,ledger);ui.history:SetPoint("TOPLEFT",ledger,"TOPLEFT",0,CONTENT_TOP);ui.history:SetSize(W,H)
    local h=ui.history;h.rows={}
    h.caption=heading(h,"",14,0,W-30)
    local columns={{"Observed",14,180,"LEFT"},{"Peak gold",194,150,"RIGHT"},{"Total acquired",344,160,"RIGHT"},{"Increase",504,166,"RIGHT"}}
    for _,def in ipairs(columns) do text(h,"GameFontNormalSmall",def[2]+4,-22,def[3]-8,14,def[4]):SetText(def[1]) end
    for n=1,9 do
        local row=CreateFrame("Frame",nil,h);row:SetPoint("TOPLEFT",h,"TOPLEFT",14,-38-(n-1)*17);row:SetSize(W-30,17)
        if n%2==1 then fill(row,0,0,W-30,17,1,1,1,.05) end
        local cells={}
        for index,key in ipairs({"time","peak","total","delta"}) do
            local def=columns[index]
            cells[key]=text(row,"GameFontHighlightSmall",def[2]-14+4,0,def[3]-8,17,def[4])
        end
        cells.frame=row;h.rows[n]=cells
    end
    h.previous=button(h,"Previous",84,function()I.historyPage=(I.historyPage or 0)-1;renderHistory()end)
    h.previous:SetPoint("TOPLEFT",h,"TOPLEFT",14,-196)
    h.page=text(h,"GameFontHighlightSmall",100,-196,96,22,"CENTER")
    h.next=button(h,"Next",84,function()I.historyPage=(I.historyPage or 0)+1;renderHistory()end)
    h.next:SetPoint("TOPLEFT",h,"TOPLEFT",198,-196)
    text(h,"GameFontDisableSmall",300,-196,W-316,22,"RIGHT"):SetText("No increase is shown across counter resets or client builds")
end
function I.Show(origin)
    if not w then
        w=CreateFrame("Frame","ForeverIRSWindow",UIParent,"ButtonFrameTemplate");I.window=w
        w:SetSize(W,H);w:SetFrameStrata("DIALOG");w:SetToplevel(true);w:SetClampedToScreen(true)
        w:SetTitle("Ironforge Revenue Service");w:SetPortraitToAsset("Interface\\AddOns\\ForeverIRS\\Assets\\Portrait")
        if w.CloseButton then w.CloseButton:SetScript("OnClick",function()w:Hide()end) end
        w:SetMovable(true);w:EnableMouse(true);w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart",function()w:StartMoving()end)
        w:SetScript("OnDragStop",function()
            w:StopMovingOrSizing();local point,_,relative,x,y=w:GetPoint()
            I.db.position={point=point,relative=relative,x=x,y=y}
        end)
        w:HookScript("OnHide",function()I.cancel(nil);if I.reportWindow then I.reportWindow:Hide() end end)
        tinsert(UISpecialFrames,"ForeverIRSWindow")
        ui={groups={},cards={},tabs={}}
        -- Header beside the portrait.
        ui.name=text(w,"GameFontHighlightLarge",62,-26,W-300,18)
        ui.identity=text(w,"GameFontHighlightSmall",62,-45,W-308,12)
        ui.age=text(w,"GameFontHighlightSmall",W-278,-27,214,14,"RIGHT")
        text(w,"GameFontNormalSmall",W-60,-27,50,14,"RIGHT"):SetText("v"..I.VERSION)
        local notice=text(w,"GameFontNormalSmall",W-226,-40,216,22,"RIGHT");notice:SetWordWrap(true)
        notice:SetText(I.PLAYER_DISCLAIMER)
        -- Only a failed request or a response with no usable statistics needs
        -- a banner. Normal fetch details remain available in copied reports.
        local check=CreateFrame("Frame",nil,w,"BackdropTemplate");ui.verification=check;I.verificationPanel=check
        check:SetPoint("TOPLEFT",w,"TOPLEFT",10,-64);check:SetSize(W-20,CHECK_HEIGHT-6)
        check:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=false,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
        check:SetBackdropColor(.06,.06,.06,.95);check:SetBackdropBorderColor(.65,.18,.12,1)
        check.title=text(check,"GameFontNormal",10,-4,W-40,16,"LEFT",RED)
        check.detail=text(check,"GameFontHighlightSmall",10,-22,W-40,24,"LEFT",RED);check.detail:SetWordWrap(true)
        makeLedger()
        -- Footer inside the inset, above the button bar.
        local footer=CreateFrame("Frame",nil,w);footer:SetPoint("BOTTOMLEFT",w,"BOTTOMLEFT",0,0);footer:SetSize(W,H)
        ui.status=text(footer,"GameFontHighlightSmall",14,-(H-60),W-28,14)
        local sourceHit=CreateFrame("Frame",nil,footer)
        sourceHit:SetPoint("TOPLEFT",footer,"TOPLEFT",14,-(H-44));sourceHit:SetSize(W-28,14)
        ui.source=text(sourceHit,"GameFontDisableSmall",0,0,W-28,14)
        sourceHit:EnableMouse(true);sourceHit:SetScript("OnEnter",explainSource);sourceHit:SetScript("OnLeave",hideTooltip)
        -- Button bar: actions on the left, the one setting on the right.
        local me=button(w,"My character",104,function()I.audit("player")end);me:SetPoint("BOTTOMLEFT",w,"BOTTOMLEFT",6,4)
        local target=button(w,"Target",80,function()I.audit("target")end);target:SetPoint("LEFT",me,"RIGHT",2,0)
        ui.refreshButton=button(w,"Refresh",80,function()I.Refresh()end);ui.refreshButton:SetPoint("LEFT",target,"RIGHT",2,0)
        ui.copyButton=button(w,"Copy report",104,openReport);ui.copyButton:SetPoint("LEFT",ui.refreshButton,"RIGHT",2,0)
        local autoLabel=text(w,"GameFontNormalSmall",0,0,100,22,"RIGHT");autoLabel:SetText("Open with Inspect")
        autoLabel:ClearAllPoints();autoLabel:SetPoint("BOTTOMRIGHT",w,"BOTTOMRIGHT",-10,4)
        ui.auto=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate");ui.auto:SetSize(22,22)
        ui.auto:SetPoint("RIGHT",autoLabel,"LEFT",0,0)
        ui.auto:SetScript("OnClick",function(self)I.db.autoInspect=self:GetChecked() and true or false end)
        makeDirectory()
        for index,name in ipairs(TABS) do
            local tab=CreateFrame("Button","ForeverIRSWindowTab"..index,w,"PanelTabButtonTemplate")
            tab:SetID(index);tab:SetText(name);tab:SetScript("OnClick",function()selectTab(index)end)
            if index==1 then tab:SetPoint("TOPLEFT",w,"BOTTOMLEFT",11,2)
            else tab:SetPoint("TOPLEFT",ui.tabs[index-1],"TOPRIGHT",3,0) end
            PanelTemplates_TabResize(tab,0);ui.tabs[index]=tab
        end
        PanelTemplates_SetNumTabs(w,#TABS)
    end
    I.FitWindows()
    w:ClearAllPoints()
    local pos=I.db.position
    if type(pos)=="table" and type(pos.point)=="string" and type(pos.relative)=="string" and type(pos.x)=="number" and type(pos.y)=="number" then
        local ok=pcall(w.SetPoint,w,pos.point,UIParent,pos.relative,pos.x,pos.y);if not ok then w:SetPoint("CENTER") end
    elseif origin=="inspect" and InspectFrame and InspectFrame:IsShown() then w:SetPoint("TOPLEFT",InspectFrame,"TOPRIGHT",12,0)
    else w:SetPoint("CENTER") end
    w:Show();I.Render()
end
