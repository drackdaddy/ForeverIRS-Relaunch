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

-- Unexplained gold: the share of a character's gold that the four itemized
-- income counters cannot account for. Computed from a capture on demand, so it
-- sends no requests, uses no events, and stores nothing in ForeverIRSDB.
I.RATING_MIN_GOLD = 1000000 -- 100g in copper; below this a single gift dominates the percentage.
I.RATING_METHOD = "Looted, quest, vendor and auction income, compared with the larger of peak gold and total gold acquired. Tracked spending is left out, so this is a low estimate."
I.RATING_NOTE = "This is not the chance that gold was bought. IRS cannot see where gold came from: gifts, alts, guild funds and player trades look the same as purchased gold."
I.RATING_LINE = I.INCOME_DISCLAIMER.." Gifts, alts, guild funds and player trades look the same."
I.RATING_MISSING = "Not rated: peak, acquired and all four income counters are needed."
-- Larger of peak and acquired, because the game does not document whether
-- trades and mail count toward acquired gold; this holds either way.
-- snapshot: a capture, or nil. Returns {percent,unexplained,received} when
-- rated, otherwise {reason}. A missing counter is never treated as zero: that
-- would inflate the percentage.
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
    return {percent=math.floor(unexplained/received*100),unexplained=unexplained,received=received}
end
