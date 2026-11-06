local _, I = ...
I.ASSESSMENT_NOTE = "These counters describe what the game reported. New characters, bank alts and specialists can have different records; missing counters and resets can affect them. The activity summary does not grade characters."
I.professionKeys = {"firstAid","cooking","fishing","alchemy","blacksmithing","enchanting","leatherworking","mining","herbalism","skinning","tailoring","engineering"}
I.activityKeys = {"questCount","kills","dungeons","disenchanted","disenchantMaterials","fishCaught","honorableKills","flights","deaths"}

function I.professions(snapshot)
    local rows={}
    for _,key in ipairs(I.professionKeys) do
        rows[#rows+1]={key=key,label=I.byKey[key][3],highest=I.byKey[key][5]==true,n=I.numeric(snapshot,key)}
    end
    table.sort(rows,function(a,b)
        if a.n==nil and b.n~=nil then return false end
        if b.n==nil and a.n~=nil then return true end
        if a.n~=b.n then return a.n>b.n end
        return a.label<b.label
    end)
    return rows
end

-- Summarize returned counters without grading a character or inferring play style.
function I.assess(snapshot)
    local known,total,positive=0,0,0
    local evidence={}
    for _,key in ipairs({"questCount","kills","dungeons","honorableKills","disenchanted","disenchantMaterials","fishCaught"}) do
        local n=I.numeric(snapshot,key)
        total=total+1
        if n~=nil then known=known+1;if n>0 then positive=positive+1 end end
        evidence[#evidence+1]=I.byKey[key][3]..": "..I.value(snapshot,key,true)
    end
    local rankKnown,rankPositive=0,0
    for _,key in ipairs(I.professionKeys) do
        local rank=I.numeric(snapshot,key)
        total=total+1
        if rank~=nil then known=known+1;rankKnown=rankKnown+1 end
        if rank and rank>0 then positive=positive+1;rankPositive=rankPositive+1 end
    end
    evidence[#evidence+1]="Professions: "..rankPositive.." with recorded ranks above zero; "..rankKnown.." / "..#I.professionKeys.." readable. Historical ranks can include unlearned professions."
    evidence[#evidence+1]="Auctions: "..I.value(snapshot,"posted",true).." posted; "..I.value(snapshot,"purchases",true).." purchases."
    return {key=known>0 and "recorded" or "unknown",title=known>0 and "Recorded activity" or "Activity counters unavailable",
        summary=known>0 and (positive.." of the "..known.." readable activity counters have values above zero. Missing values are not zero.")
            or "This capture has no readable activity counters. Missing values are not zero.",
        tone=known>0 and "neutral" or "muted",known=known,total=total,positive=positive,evidence=evidence,
        coverage=known.." / "..total.." activity counters readable · missing is not zero"}
end

-- Risk factor: the share of a character's gold that the four itemized income
-- counters cannot account for, placed on a four-step scale. It gives players
-- data to weigh and accuses no one. Computed from a capture on demand, so it
-- sends no requests, uses no events, and stores nothing in ForeverIRSDB.
I.RATING_MIN_GOLD = 50000 -- 5g in copper.
-- Each level's name and the lowest unexplained percentage that reaches it.
I.RISK_LEVELS = {{"Low",0},{"Moderate",25},{"Elevated",50},{"High",75}}
I.RISK_SCALE = "Scale: Low under 25%, Moderate 25-49%, Elevated 50-74%, High 75% or more unexplained."
I.RATING_METHOD = "Looted, quest, vendor and auction income, compared with the larger of peak gold and total gold acquired. Tracked spending is left out, so this is a low estimate. Traded gold only shows if it raised peak gold, so a Low reading does not clear anyone."
I.RATING_NOTE = "A risk factor is not an accusation or the chance that gold was bought. IRS cannot see where gold came from: gifts, alts, guild funds and player trades look the same as purchased gold."
I.RATING_LINE = I.INCOME_DISCLAIMER.." Gifts, alts, guild funds and player trades look the same."
I.RATING_MISSING = "Not rated: peak, acquired and all four income counters are needed."
-- Larger of peak and acquired: on build 1.60.1.70790 a test trade did not raise
-- acquired gold, so traded gold can only appear here through peak. Mail is untested.
-- snapshot: a capture, or nil. Returns {percent,level,risk,unexplained,received,
-- itemized,peak,acquired} when rated, otherwise {reason}. A missing counter is
-- never treated as zero: that would inflate the percentage.
function I.rating(snapshot)
    local itemized=0
    for _,key in ipairs({"looted","quests","vendors","auctions"}) do
        local n=I.numeric(snapshot,key)
        if n==nil then return {reason=I.RATING_MISSING} end
        itemized=itemized+n
    end
    local peak,acquired=I.numeric(snapshot,"peak"),I.numeric(snapshot,"acquired")
    if peak==nil or acquired==nil then return {reason=I.RATING_MISSING} end
    local received=math.max(peak,acquired)
    if received<I.RATING_MIN_GOLD then
        return {reason="Not rated: under "..I.quantity(I.RATING_MIN_GOLD/10000).."g recorded."}
    end
    local unexplained=math.max(0,received-itemized)
    -- Multiply first: 0.29*100 falls just short of 29 and would land one percent low.
    local percent=math.floor(unexplained*100/received)
    local level=1
    for n,def in ipairs(I.RISK_LEVELS) do if percent>=def[2] then level=n end end
    return {percent=percent,level=level,risk=I.RISK_LEVELS[level][1],unexplained=unexplained,
        received=received,itemized=itemized,peak=peak,acquired=acquired}
end
